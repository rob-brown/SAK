defmodule SakWeb.ChatLive.Subagents do
  @moduledoc false

  alias Phoenix.Component
  alias Phoenix.PubSub
  alias Sak.Chat
  alias Sak.Gateway
  alias Sak.SubagentRows

  def reset(socket) do
    socket
    |> leave()
    |> Component.assign(
      subagents: [],
      subagents_selected: 0,
      show_finished_subagents?: false
    )
  end

  def view(socket) do
    case selected(socket.assigns) do
      nil -> socket
      row -> socket |> leave() |> enter(row)
    end
  end

  def close_view(socket), do: leave(socket)

  def reattach(%{assigns: %{viewed: %{id: id}}} = socket) do
    client().request("attach", %{"conversationId" => id})
    socket
  end

  def reattach(socket), do: socket

  def viewed_snapshot(%{assigns: %{viewed: viewed}} = socket, snapshot) do
    Component.assign(socket, viewed: %{viewed | chat: Chat.from_snapshot(snapshot)})
  end

  def viewed_events(%{assigns: %{viewed: viewed}} = socket, events) do
    {chat, _ops} = Chat.apply_events(viewed.chat, events)
    Component.assign(socket, viewed: %{viewed | chat: chat})
  end

  def viewed_items(%{viewed: %{chat: chat}}), do: Chat.items(chat)

  defp enter(socket, row) do
    PubSub.subscribe(Sak.PubSub, Gateway.conversation_topic(row.id))

    case client().request("attach", %{"conversationId" => row.id}) do
      {:ok, _result} ->
        viewed = %{id: row.id, label: row.label, persona: row.persona, chat: %Chat{}}
        Component.assign(socket, viewed: viewed, last_error: nil)

      {:error, reason} ->
        PubSub.unsubscribe(Sak.PubSub, Gateway.conversation_topic(row.id))
        Component.assign(socket, last_error: reason)
    end
  end

  defp leave(%{assigns: %{viewed: %{id: id}}} = socket) do
    PubSub.unsubscribe(Sak.PubSub, Gateway.conversation_topic(id))
    client().request("detach", %{"conversationId" => id})
    Component.assign(socket, viewed: nil)
  end

  defp leave(socket), do: Component.assign(socket, viewed: nil)

  def refresh(%{assigns: %{chat_tab: :subagents, current_id: id}} = socket) when is_integer(id) do
    case client().request("list_subagents", %{"conversationId" => id}) do
      {:ok, %{"subagents" => subagents}} ->
        socket |> Component.assign(subagents: subagents) |> clamp()

      {:error, reason} ->
        Component.assign(socket, last_error: reason)
    end
  end

  def refresh(socket), do: socket

  def rows(assigns), do: SubagentRows.rows(assigns.subagents, assigns.show_finished_subagents?)

  def counts(assigns), do: SubagentRows.counts(assigns.subagents)

  def move(socket, delta) do
    Component.update(socket, :subagents_selected, &(&1 + delta))
    |> clamp()
  end

  def select_index(socket, index) do
    socket |> Component.assign(subagents_selected: index) |> clamp()
  end

  def toggle_finished(socket) do
    socket
    |> Component.update(:show_finished_subagents?, &(!&1))
    |> clamp()
  end

  def abort_selected(socket) do
    case selected(socket.assigns) do
      %{live?: true, id: id} ->
        case client().request("abort", %{"conversationId" => id}) do
          {:ok, _result} -> refresh(socket)
          {:error, reason} -> Component.assign(socket, last_error: reason)
        end

      _finished_or_none ->
        socket
    end
  end

  def selected(assigns), do: Enum.at(rows(assigns), assigns.subagents_selected)

  defp clamp(socket) do
    last = max(length(rows(socket.assigns)) - 1, 0)
    Component.update(socket, :subagents_selected, &(&1 |> max(0) |> min(last)))
  end

  defp client do
    Application.get_env(:sak, :gateway_client, Sak.Gateway)
  end
end
