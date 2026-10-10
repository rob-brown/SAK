defmodule Sak.Gateway do
  @moduledoc """
  Owns the Node gateway process and speaks its JSON-lines protocol over stdio.

  Requests are matched to replies by id. Pushed `snapshot` and `events`
  messages are broadcast on `Sak.Gateway.conversation_topic/1`. After a
  (re)start the process broadcasts `:gateway_started` on `started_topic/0`
  so subscribers can re-attach.
  """

  use GenServer

  alias Phoenix.PubSub

  require Logger

  @pubsub Sak.PubSub
  @started_topic "gateway"
  @default_timeout 15_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  def child_spec(opts) do
    %{id: Keyword.get(opts, :name, __MODULE__), start: {__MODULE__, :start_link, [opts]}}
  end

  def started_topic, do: @started_topic

  def conversation_topic(conversation_id) do
    "conversation:#{conversation_id}"
  end

  def request(type, params \\ %{}, opts \\ []) do
    server = Keyword.get(opts, :server, __MODULE__)
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    try do
      GenServer.call(server, {:request, type, params}, timeout)
    catch
      :exit, {:timeout, _} -> {:error, "gateway timed out"}
      :exit, _ -> {:error, "gateway unavailable"}
    end
  end

  @impl true
  def init(opts) do
    port = open_port(opts)
    {:ok, %{port: port, buffer: "", pending: %{}, next_id: 1}, {:continue, :announce}}
  end

  @impl true
  def handle_continue(:announce, state) do
    PubSub.broadcast(@pubsub, @started_topic, :gateway_started)
    {:noreply, state}
  end

  @impl true
  def handle_call({:request, type, params}, from, state) do
    id = Integer.to_string(state.next_id)
    send_command(state.port, Map.merge(params, %{"id" => id, "type" => type}))
    pending = Map.put(state.pending, id, from)
    {:noreply, %{state | pending: pending, next_id: state.next_id + 1}}
  end

  @impl true
  def handle_info({port, {:data, {:noeol, chunk}}}, %{port: port} = state) do
    {:noreply, %{state | buffer: state.buffer <> chunk}}
  end

  def handle_info({port, {:data, {:eol, line}}}, %{port: port} = state) do
    handle_line(state.buffer <> line, %{state | buffer: ""})
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.error("gateway exited with status #{status}")
    {:stop, {:gateway_exited, status}, state}
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    Enum.each(state.pending, fn {_id, from} -> GenServer.reply(from, {:error, "gateway down"}) end)

    :ok
  end

  defp handle_line(line, state) do
    case Jason.decode(line) do
      {:ok, message} ->
        {:noreply, dispatch(message, state)}

      {:error, _reason} ->
        Logger.warning("gateway sent non-JSON output: #{inspect(line)}")
        {:noreply, state}
    end
  end

  defp dispatch(%{"type" => "reply", "id" => nil, "error" => error}, state) do
    Logger.warning("gateway error: #{error}")
    state
  end

  defp dispatch(%{"type" => "reply", "id" => id} = message, state) do
    {from, pending} = Map.pop(state.pending, id)
    reply_to(from, reply_value(message))
    %{state | pending: pending}
  end

  defp dispatch(%{"type" => "snapshot", "conversationId" => id, "snapshot" => snapshot}, state) do
    broadcast(id, {:gateway_snapshot, id, snapshot})
    state
  end

  defp dispatch(%{"type" => "events", "conversationId" => id, "events" => events}, state) do
    broadcast(id, {:gateway_events, id, events})
    state
  end

  defp dispatch(message, state) do
    Logger.warning("gateway sent unknown message: #{inspect(message)}")
    state
  end

  defp reply_value(%{"ok" => true, "result" => result}) do
    {:ok, result}
  end

  defp reply_value(%{"error" => error}) do
    {:error, error}
  end

  defp reply_to(nil, _value) do
    :ok
  end

  defp reply_to(from, value) do
    GenServer.reply(from, value)
  end

  defp broadcast(conversation_id, message) do
    PubSub.broadcast(@pubsub, conversation_topic(conversation_id), message)
  end

  defp send_command(port, command) do
    Port.command(port, Jason.encode!(command) <> "\n")
  end

  defp open_port(opts) do
    env =
      Enum.map(Keyword.get(opts, :env, []), fn {key, value} ->
        {to_charlist(key), to_charlist(value)}
      end)

    Port.open({:spawn_executable, Keyword.fetch!(opts, :executable)}, [
      :binary,
      :exit_status,
      {:line, 4_000_000},
      {:args, Keyword.get(opts, :args, [])},
      {:cd, Keyword.get(opts, :cd, File.cwd!())},
      {:env, env}
    ])
  end
end
