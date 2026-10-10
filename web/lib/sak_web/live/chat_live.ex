defmodule SakWeb.ChatLive do
  use SakWeb, :live_view

  alias Phoenix.PubSub
  alias Sak.Chat
  alias Sak.Gateway

  import SakWeb.ChatComponents

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(
        chat: %Chat{},
        conversations: [],
        current_id: nil,
        error: nil,
        default_cwd: default_cwd(),
        gateway_up?: false
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
  def handle_event("send", %{"content" => content}, socket) do
    {:noreply, submit(socket, String.trim(content))}
  end

  def handle_event("abort", _params, socket) do
    {:noreply, request(socket, "abort", %{"conversationId" => socket.assigns.current_id})}
  end

  def handle_event("new_session", %{"cwd" => cwd}, socket) do
    case client().request("create_conversation", %{"cwd" => cwd}) do
      {:ok, %{"conversationId" => id}} ->
        {:noreply, socket |> refresh_conversations() |> push_patch(to: ~p"/c/#{id}")}

      {:error, reason} ->
        {:noreply, assign(socket, error: reason)}
    end
  end

  @impl true
  def handle_info({:gateway_snapshot, id, snapshot}, %{assigns: %{current_id: id}} = socket) do
    chat = Chat.from_snapshot(snapshot)
    {:noreply, socket |> assign(chat: chat) |> stream(:messages, Chat.items(chat), reset: true)}
  end

  def handle_info({:gateway_events, id, events}, %{assigns: %{current_id: id}} = socket) do
    {chat, ops} = Chat.apply_events(socket.assigns.chat, events)
    {:noreply, socket |> assign(chat: chat) |> apply_ops(ops)}
  end

  def handle_info(:gateway_started, socket) do
    {:noreply, socket |> assign(gateway_up?: true) |> refresh_conversations() |> attach()}
  end

  def handle_info(_message, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div id="sak" phx-hook="KeyRouter" class="flex h-dvh bg-neutral-950 text-neutral-200">
        <aside id="sidebar" class="flex w-72 shrink-0 flex-col border-r border-neutral-800">
          <.form
            for={%{}}
            id="new-session-form"
            phx-submit="new_session"
            class="flex gap-2 border-b border-neutral-800 p-3"
          >
            <input
              id="new-session-cwd"
              name="cwd"
              value={@default_cwd}
              class="min-w-0 flex-1 rounded border border-neutral-700 bg-neutral-900 px-2 py-1 text-sm"
            />
            <button
              id="new-session-button"
              class="rounded bg-cyan-600 px-3 py-1 text-sm font-medium text-white hover:bg-cyan-500"
            >
              New
            </button>
          </.form>
          <ul id="conversations" class="flex-1 overflow-y-auto">
            <li :for={conversation <- @conversations} id={"conversation-#{conversation["id"]}"}>
              <.link
                patch={~p"/c/#{conversation["id"]}"}
                class={[
                  "block px-3 py-2 text-sm hover:bg-neutral-900",
                  conversation["id"] == @current_id && "bg-neutral-800"
                ]}
              >
                <div class="truncate font-medium">{label(conversation)}</div>
                <div class="truncate text-xs text-neutral-500">{conversation["cwd"]}</div>
              </.link>
            </li>
          </ul>
          <div
            id="gateway-status"
            class="border-t border-neutral-800 px-3 py-2 text-xs text-neutral-500"
          >
            {gateway_label(@gateway_up?)}
          </div>
        </aside>

        <main id="chat-pane" class="flex min-w-0 flex-1 flex-col">
          <div
            id="chat-history"
            phx-hook="ChatScroll"
            class="flex-1 overflow-y-auto"
          >
            <p :if={@current_id == nil} id="no-session" class="p-6 text-neutral-500">
              no active session
            </p>
            <div id="chat-messages" phx-update="stream" class="mx-auto max-w-3xl space-y-1 py-4">
              <.message :for={{dom_id, item} <- @streams.messages} id={dom_id} item={item} />
            </div>
          </div>

          <div id="status-line" class="border-t border-neutral-800 px-4 py-1 text-xs text-neutral-500">
            {status_line(assigns)}
          </div>

          <.form
            :if={@current_id}
            for={%{}}
            id="prompt-form"
            phx-submit="send"
            class="flex gap-2 border-t border-neutral-800 p-3"
          >
            <textarea
              id="prompt-input"
              name="content"
              rows="2"
              phx-hook="PromptBox"
              placeholder="message — enter to send, shift+enter for a newline"
              class="min-w-0 flex-1 resize-none rounded border border-neutral-700 bg-neutral-900 px-3 py-2"
            ></textarea>
            <button
              :if={@chat.running?}
              id="abort-button"
              type="button"
              phx-click="abort"
              class="rounded bg-red-700 px-3 text-sm font-medium text-white hover:bg-red-600"
            >
              Abort
            </button>
          </.form>
        </main>
      </div>
    </Layouts.app>
    """
  end

  defp connect(socket, false) do
    socket
  end

  defp connect(socket, true) do
    PubSub.subscribe(Sak.PubSub, Gateway.started_topic())
    socket |> assign(gateway_up?: true) |> refresh_conversations()
  end

  defp select(socket, id) do
    socket = assign(socket, current_id: id, chat: %Chat{}, error: nil)
    socket = stream(socket, :messages, [], reset: true)
    attach(socket)
  end

  defp deselect(socket) do
    socket
    |> assign(current_id: nil, chat: %Chat{})
    |> stream(:messages, [], reset: true)
  end

  defp attach(%{assigns: %{current_id: nil}} = socket) do
    socket
  end

  defp attach(%{assigns: %{current_id: id}} = socket) do
    if connected?(socket) do
      PubSub.subscribe(Sak.PubSub, Gateway.conversation_topic(id))
      request(socket, "attach", %{"conversationId" => id})
    else
      socket
    end
  end

  defp submit(socket, "") do
    socket
  end

  defp submit(socket, content) do
    params = %{
      "conversationId" => socket.assigns.current_id,
      "content" => content,
      "whenBusy" => "steer",
      "requestId" => request_id()
    }

    request(socket, "submit", params)
  end

  defp refresh_conversations(socket) do
    case client().request("list_conversations", %{}) do
      {:ok, %{"conversations" => conversations}} ->
        assign(socket, conversations: Enum.sort_by(conversations, & &1["id"], :desc))

      {:error, reason} ->
        assign(socket, error: reason)
    end
  end

  defp request(socket, type, params) do
    case client().request(type, params) do
      {:ok, _result} -> assign(socket, error: nil)
      {:error, reason} -> assign(socket, error: reason)
    end
  end

  defp request_id do
    16 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  end

  defp gateway_label(true) do
    "gateway connected"
  end

  defp gateway_label(false) do
    "gateway connecting…"
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
    stream(socket, :messages, Chat.items(socket.assigns.chat), reset: true)
  end

  defp client do
    Application.get_env(:sak, :gateway_client, Gateway)
  end

  defp default_cwd do
    Application.get_env(:sak, :default_cwd) || System.user_home!()
  end

  defp label(conversation) do
    name = conversation["cwd"] |> to_string() |> Path.basename()
    "#{name} ##{conversation["id"]}"
  end

  defp status_line(%{error: error}) when is_binary(error) do
    "error: #{error}"
  end

  defp status_line(%{chat: %{failure: failure}}) when is_binary(failure) do
    "failed: #{failure}"
  end

  defp status_line(%{chat: %{running?: true, running_tools: tools}}) when map_size(tools) > 0 do
    "running #{tools |> Map.values() |> Enum.join(", ")}…"
  end

  defp status_line(%{chat: %{running?: true}}) do
    "working…"
  end

  defp status_line(%{chat: chat}) do
    model = get_in(chat.agent, ["model", "modelId"]) || "idle"
    "#{model} · #{Chat.total_tokens(chat)} tokens"
  end
end
