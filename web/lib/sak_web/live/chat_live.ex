defmodule SakWeb.ChatLive do
  use SakWeb, :live_view

  alias Phoenix.PubSub
  alias Sak.Chat
  alias Sak.ConnectionLog
  alias Sak.Gateway
  alias Sak.Hints
  alias SakWeb.ChatLive.Command
  alias SakWeb.ChatLive.Items
  alias SakWeb.ChatLive.Mention
  alias SakWeb.ChatLive.Models
  alias SakWeb.ChatLive.NewSession
  alias SakWeb.ChatLive.Search
  alias SakWeb.ChatLive.Sessions

  import SakWeb.ChatLive.Render
  import SakWeb.ChatComponents
  import SakWeb.Overlays

  @refresh_interval 5_000

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(
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
        sidebar_tab: :sessions,
        focused_pane: :sessions_and_logs,
        zoomed_pane: nil,
        help_open?: false,
        help_search: "",
        models: nil,
        new_session: nil,
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
      )
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
    {:noreply, socket |> assign(chat: chat) |> Items.refresh()}
  end

  def handle_info({:gateway_events, id, events}, %{assigns: %{current_id: id}} = socket) do
    {chat, ops} = Chat.apply_events(socket.assigns.chat, events)
    {:noreply, socket |> assign(chat: chat) |> apply_ops(ops)}
  end

  def handle_info(:gateway_started, socket) do
    socket =
      socket |> assign(gateway_up?: true) |> log("gateway started") |> refresh_conversations()

    {:noreply, attach(socket)}
  end

  def handle_info(:refresh_conversations, socket) do
    Process.send_after(self(), :refresh_conversations, @refresh_interval)
    {:noreply, refresh_conversations(socket)}
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
  def handle_event("key", %{"key" => "escape"}, %{assigns: %{help_open?: true}} = socket) do
    {:noreply, close_help(socket)}
  end

  def handle_event("key", _params, %{assigns: %{help_open?: true}} = socket) do
    {:noreply, socket}
  end

  def handle_event("key", %{"key" => "escape"}, %{assigns: %{models: %{}}} = socket) do
    {:noreply, Models.close(socket)}
  end

  def handle_event("key", _params, %{assigns: %{models: %{}}} = socket) do
    {:noreply, socket}
  end

  def handle_event("key", %{"key" => "escape"}, %{assigns: %{new_session: %{}}} = socket) do
    {:noreply, NewSession.back(socket)}
  end

  def handle_event("key", _params, %{assigns: %{new_session: %{}}} = socket) do
    {:noreply, socket}
  end

  def handle_event("key", %{"key" => "escape"}, %{assigns: %{chat_search_open?: true}} = socket) do
    {:noreply, Search.close(socket)}
  end

  def handle_event("key", _params, %{assigns: %{chat_search_open?: true}} = socket) do
    {:noreply, socket}
  end

  def handle_event("key", %{"key" => "escape"}, %{assigns: %{command_open?: true}} = socket) do
    {:noreply, Command.close(socket)}
  end

  def handle_event("key", _params, %{assigns: %{command_open?: true}} = socket) do
    {:noreply, socket}
  end

  def handle_event("key", %{"key" => key}, socket) do
    {:noreply, key(key, socket)}
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

  def handle_event("focus_chat_history", _params, socket) do
    {:noreply, focus_pane(socket, :chat_history)}
  end

  def handle_event("toggle_row", %{"index" => index}, socket) do
    {:noreply,
     socket |> Sessions.toggle_at(String.to_integer(index)) |> focus_pane(:sessions_and_logs)}
  end

  def handle_event("wizard_query", %{"query" => query}, socket) do
    {:noreply, NewSession.set_query(socket, query)}
  end

  def handle_event("wizard_move", %{"delta" => delta}, socket) do
    {:noreply, NewSession.move(socket, delta)}
  end

  def handle_event("wizard_accept", _params, socket) do
    {:noreply, NewSession.accept(socket)}
  end

  def handle_event("wizard_back", _params, socket) do
    {:noreply, NewSession.back(socket)}
  end

  def handle_event("wizard_select_index", %{"index" => index}, socket) do
    {:noreply, NewSession.select_index(socket, String.to_integer(index))}
  end

  def handle_event("models_search", %{"query" => query}, socket) do
    {:noreply, Models.search(socket, query)}
  end

  def handle_event("close_models", _params, socket) do
    {:noreply, Models.close(socket)}
  end

  def handle_event("help_search", %{"query" => query}, socket) do
    {:noreply, assign(socket, help_search: query)}
  end

  def handle_event("close_help", _params, socket) do
    {:noreply, close_help(socket)}
  end

  def handle_event("chat_search_change", %{"term" => term}, socket) do
    {:noreply, Search.change(socket, term)}
  end

  def handle_event("chat_search_next", _params, socket) do
    {:noreply, Search.confirm(socket)}
  end

  def handle_event("close_chat_search", _params, socket) do
    {:noreply, Search.close(socket)}
  end

  def handle_event("mention_query", %{"query" => query}, socket) do
    {:noreply, Mention.query(socket, query)}
  end

  def handle_event("mention_close", _params, socket) do
    {:noreply, Mention.close(socket)}
  end

  def handle_event("mention_move", %{"delta" => delta}, socket) do
    {:noreply, Mention.move(socket, delta)}
  end

  def handle_event("mention_select", _params, socket) do
    {:noreply, Mention.select(socket)}
  end

  def handle_event("mention_select_index", %{"index" => index}, socket) do
    {:noreply, Mention.select_index(socket, String.to_integer(index))}
  end

  def handle_event("command_open", _params, socket) do
    {:noreply, Command.open(socket)}
  end

  def handle_event("command_query", %{"query" => query}, socket) do
    {:noreply, Command.query(socket, query)}
  end

  def handle_event("command_close", _params, socket) do
    {:noreply, Command.close(socket)}
  end

  def handle_event("command_move", %{"delta" => delta}, socket) do
    {:noreply, Command.move(socket, delta)}
  end

  def handle_event("command_run", _params, socket) do
    {:noreply, Command.run(socket)}
  end

  def handle_event("command_run_index", %{"index" => index}, socket) do
    {:noreply, Command.run_index(socket, String.to_integer(index))}
  end

  defp key(":", socket) do
    Command.open(socket)
  end

  defp key("?", socket) do
    assign(socket, help_open?: true, help_search: "")
  end

  defp key("z", socket) do
    toggle_zoom(socket)
  end

  defp key("t", socket) do
    socket |> update(:thinking_visible?, &(!&1)) |> Items.refresh()
  end

  defp key("o", socket) do
    socket |> update(:tool_output_visible?, &(!&1)) |> Items.refresh()
  end

  defp key("/", %{assigns: %{focused_pane: :chat_history}} = socket) do
    Search.open(socket)
  end

  defp key("N", %{assigns: %{focused_pane: :chat_history}} = socket) do
    Search.jump(socket, -1)
  end

  defp key("n", socket) do
    new_key(socket)
  end

  defp key(bracket, socket) when bracket in ["[", "]"] do
    toggle_sidebar_tab(socket)
  end

  defp key("0", socket) do
    focus_pane(socket, :chat_history)
  end

  defp key("1", socket) do
    focus_pane(socket, :sessions_and_logs)
  end

  defp key("enter", socket) do
    enter_key(socket)
  end

  defp key(code, socket) when code in ["j", "down"] do
    move_selection(socket, 1)
  end

  defp key(code, socket) when code in ["k", "up"] do
    move_selection(socket, -1)
  end

  defp key(_key, socket) do
    socket
  end

  defp new_key(%{assigns: %{focused_pane: :chat_history}} = socket) do
    Search.jump(socket, 1)
  end

  defp new_key(%{assigns: %{sidebar_tab: :sessions}} = socket) do
    NewSession.open(socket)
  end

  defp new_key(socket) do
    socket
  end

  defp enter_key(%{assigns: %{focused_pane: :sessions_and_logs, sidebar_tab: :sessions}} = socket) do
    case Sessions.cursor_row(socket.assigns) do
      {:session, session} -> push_patch(socket, to: ~p"/c/#{session["id"]}")
      {:header, _header} -> Sessions.toggle(socket)
      nil -> socket
    end
  end

  defp enter_key(socket), do: socket

  defp move_selection(
         %{assigns: %{focused_pane: :sessions_and_logs, sidebar_tab: :sessions}} = socket,
         delta
       ) do
    Sessions.move(socket, delta)
  end

  defp move_selection(socket, _delta), do: socket

  defp toggle_sidebar_tab(%{assigns: %{focused_pane: :sessions_and_logs}} = socket) do
    update(socket, :sidebar_tab, fn
      :sessions -> :logs
      :logs -> :sessions
    end)
  end

  defp toggle_sidebar_tab(socket), do: socket

  defp tab_from("logs"), do: :logs
  defp tab_from(_tab), do: :sessions

  defp close_help(socket) do
    assign(socket, help_open?: false, help_search: "")
  end

  defp focus_pane(%{assigns: %{zoomed_pane: nil}} = socket, pane) do
    assign(socket, focused_pane: pane)
  end

  defp focus_pane(socket, pane) do
    assign(socket, focused_pane: pane, zoomed_pane: pane)
  end

  defp toggle_zoom(%{assigns: %{zoomed_pane: nil, focused_pane: pane}} = socket) do
    assign(socket, zoomed_pane: pane)
  end

  defp toggle_zoom(socket) do
    assign(socket, zoomed_pane: nil)
  end

  defp connect(socket, false), do: socket

  defp connect(socket, true) do
    PubSub.subscribe(Sak.PubSub, Gateway.started_topic())
    Process.send_after(self(), :refresh_conversations, @refresh_interval)
    socket |> assign(gateway_up?: true) |> log("connected") |> refresh_conversations()
  end

  defp select(socket, id) do
    socket
    |> assign(current_id: id, chat: %Chat{}, last_error: nil, focused_pane: :chat_history)
    |> assign(zoomed_pane: nil)
    |> Items.refresh()
    |> attach()
  end

  defp deselect(socket) do
    socket |> assign(current_id: nil, chat: %Chat{}) |> Items.refresh()
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

    socket |> request("submit", params) |> update(:form_generation, &(&1 + 1))
  end

  defp when_busy("follow_up"), do: "followUp"
  defp when_busy(_queue), do: "steer"

  defp refresh_conversations(socket) do
    case client().request("list_conversations", %{}) do
      {:ok, %{"conversations" => conversations}} ->
        socket
        |> assign(conversations: Enum.sort_by(conversations, & &1["id"], :desc))
        |> Sessions.rebuild()

      {:error, reason} ->
        assign(socket, last_error: reason)
    end
  end

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
