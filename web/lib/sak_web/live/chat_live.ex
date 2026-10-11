defmodule SakWeb.ChatLive do
  use SakWeb, :live_view

  alias Phoenix.PubSub
  alias Sak.Chat
  alias Sak.ConnectionLog
  alias Sak.EntryRows
  alias Sak.Gateway
  alias Sak.Hints
  alias SakWeb.ChatLive.Entries
  alias SakWeb.ChatLive.Events
  alias SakWeb.ChatLive.Items
  alias SakWeb.ChatLive.Keys
  alias SakWeb.ChatLive.Mention
  alias SakWeb.ChatLive.NewSession
  alias SakWeb.ChatLive.Permission
  alias SakWeb.ChatLive.Search
  alias SakWeb.ChatLive.Sessions

  import SakWeb.ChatComponents
  import SakWeb.ChatLive.Render
  import SakWeb.Dialogs
  import SakWeb.Overlays
  import SakWeb.WizardOverlay

  @refresh_interval 5_000

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(initial_assigns())
      |> stream_configure(:messages, dom_id: & &1.id)
      |> stream(:messages, [])

    {:ok, connect(socket, connected?(socket))}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    {:noreply, select(socket, String.to_integer(id))}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, deselect(socket)}
  end

  @impl true
  def handle_info({:gateway_snapshot, id, snapshot}, %{assigns: %{current_id: id}} = socket) do
    chat = Chat.from_snapshot(snapshot)
    {:noreply, socket |> assign(chat: chat) |> Items.refresh() |> Entries.refresh()}
  end

  def handle_info({:gateway_events, id, events}, %{assigns: %{current_id: id}} = socket) do
    {chat, ops} = Chat.apply_events(socket.assigns.chat, events)
    {:noreply, socket |> assign(chat: chat) |> apply_ops(ops) |> Entries.refresh()}
  end

  def handle_info({:gateway_permission, id, request}, %{assigns: %{current_id: id}} = socket) do
    {:noreply, Permission.received(socket, request)}
  end

  def handle_info(
        {:gateway_permission_resolved, id, request_id},
        %{assigns: %{current_id: id}} = socket
      ) do
    {:noreply, Permission.resolved(socket, request_id)}
  end

  def handle_info(:gateway_started, socket) do
    socket =
      socket
      |> assign(gateway_up?: true)
      |> Permission.reset()
      |> log("gateway started")
      |> Sessions.refresh()

    {:noreply, attach(socket)}
  end

  def handle_info(:refresh_conversations, socket) do
    Process.send_after(self(), :refresh_conversations, @refresh_interval)
    {:noreply, Sessions.refresh(socket)}
  end

  def handle_info({:wizard_index, root, directories}, socket) do
    {:noreply, NewSession.index_received(socket, root, directories)}
  end

  def handle_info({:mention_index, token, files}, socket) do
    {:noreply, Mention.receive_index(socket, token, files)}
  end

  def handle_info(_message, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("key", %{"key" => key}, socket) do
    {:noreply, Keys.handle(key, socket)}
  end

  def handle_event("send", %{"content" => content} = params, socket) do
    {:noreply, submit(socket, String.trim(content), params["queue"])}
  end

  def handle_event("abort", _params, socket) do
    {:noreply, request(socket, "abort", %{"conversationId" => socket.assigns.current_id})}
  end

  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, sidebar_tab: tab_from(tab), focused_pane: :sessions_and_logs)}
  end

  def handle_event("select_session", %{"id" => id}, socket) do
    {:noreply, push_patch(socket, to: ~p"/c/#{id}")}
  end

  def handle_event("switch_chat_tab", %{"tab" => tab}, socket) do
    {:noreply, socket |> Entries.show(tab) |> Keys.focus_pane(:chat_history)}
  end

  def handle_event("entries_select", %{"index" => index}, socket) do
    {:noreply,
     socket |> Entries.select_index(String.to_integer(index)) |> Entries.toggle_detail()}
  end

  def handle_event("focus_chat_history", _params, socket) do
    {:noreply, Keys.focus_pane(socket, :chat_history)}
  end

  def handle_event("toggle_row", %{"index" => index}, socket) do
    socket = socket |> Sessions.toggle_at(String.to_integer(index))
    {:noreply, Keys.focus_pane(socket, :sessions_and_logs)}
  end

  def handle_event(event, params, socket) do
    {:noreply, Events.handle(event, params, socket)}
  end

  defp initial_assigns do
    [
      chat: %Chat{},
      conversations: [],
      current_id: nil,
      default_cwd: default_cwd(),
      home: System.user_home() || default_cwd(),
      gateway_up?: false,
      last_error: nil,
      last_notice: "",
      form_generation: 0,
      connection_log: ConnectionLog.new(),
      session_rows: [],
      project_labels: %{},
      collapsed_projects: MapSet.new(),
      sessions_selected: 0,
      sessions_filter: "",
      sessions_filter_open?: false,
      chat_tab: :chat,
      entry_rows: [],
      entries_selected: 0,
      entries_open: MapSet.new(),
      show_archived?: false,
      sidebar_tab: :sessions,
      focused_pane: :sessions_and_logs,
      zoomed_pane: nil,
      help_open?: false,
      help_search: "",
      models: nil,
      new_session: nil,
      confirm: nil,
      permissions: [],
      rename: nil,
      command_open?: false,
      command_query: "",
      command_selected: 0,
      command_results: [],
      thinking_visible?: true,
      tool_output_visible?: false,
      chat_search_open?: false,
      chat_search_term: "",
      chat_search_match_index: nil,
      mention_open?: false,
      mention_query: "",
      mention_selected: 0,
      mention_base_cwd: nil,
      mention_root: nil,
      mention_files: [],
      mention_loading?: false,
      mention_index_token: 0
    ]
  end

  defp tab_from("logs"), do: :logs
  defp tab_from(_tab), do: :sessions

  defp connect(socket, false), do: socket

  defp connect(socket, true) do
    PubSub.subscribe(Sak.PubSub, Gateway.started_topic())
    Process.send_after(self(), :refresh_conversations, @refresh_interval)
    socket |> assign(gateway_up?: true) |> log("connected") |> Sessions.refresh()
  end

  defp select(socket, id) do
    socket
    |> assign(
      current_id: id,
      chat: %Chat{},
      last_error: nil,
      focused_pane: :chat_history,
      zoomed_pane: nil
    )
    |> Permission.reset()
    |> Entries.reset()
    |> Items.refresh()
    |> attach()
  end

  defp deselect(socket) do
    socket
    |> assign(current_id: nil, chat: %Chat{})
    |> Permission.reset()
    |> Entries.reset()
    |> Items.refresh()
  end

  defp attach(%{assigns: %{current_id: nil}} = socket), do: socket

  defp attach(%{assigns: %{current_id: id}} = socket) do
    if connected?(socket) do
      PubSub.subscribe(Sak.PubSub, Gateway.conversation_topic(id))
      socket |> log("attach ##{id}") |> request("attach", %{"conversationId" => id})
    else
      socket
    end
  end

  defp submit(socket, "", _queue), do: socket

  defp submit(%{assigns: %{current_id: nil}} = socket, _content, _queue) do
    assign(socket, last_error: "no active session")
  end

  defp submit(socket, content, queue) do
    params = %{
      "conversationId" => socket.assigns.current_id,
      "content" => content,
      "whenBusy" => when_busy(queue),
      "requestId" => request_id()
    }

    socket
    |> assign(last_notice: "")
    |> request("submit", params)
    |> update(:form_generation, &(&1 + 1))
  end

  defp when_busy("follow_up"), do: "followUp"
  defp when_busy(_queue), do: "steer"

  defp request(socket, type, params) do
    case client().request(type, params) do
      {:ok, _result} -> assign(socket, last_error: nil)
      {:error, reason} -> socket |> assign(last_error: reason) |> log("#{type} failed: #{reason}")
    end
  end

  defp log(socket, line) do
    time = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_time()
    update(socket, :connection_log, &ConnectionLog.append(&1, "#{time}  #{line}"))
  end

  defp request_id do
    16 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  end

  defp apply_ops(socket, ops) do
    Enum.reduce(ops, socket, &apply_op/2)
  end

  defp apply_op({:insert, item}, socket) do
    stream_insert(socket, :messages, item)
  end

  defp apply_op({:delete, item}, socket) do
    stream_delete(socket, :messages, item)
  end

  defp apply_op(:reset, socket) do
    Items.refresh(socket)
  end

  defp client do
    Application.get_env(:sak, :gateway_client, Gateway)
  end

  defp default_cwd do
    Application.get_env(:sak, :default_cwd) || System.user_home!()
  end
end
