defmodule SakWeb.ChatLive.Keys do
  @moduledoc false

  use Phoenix.VerifiedRoutes, endpoint: SakWeb.Endpoint, router: SakWeb.Router

  import Phoenix.Component, only: [assign: 2, update: 3]
  import Phoenix.LiveView, only: [push_patch: 2]

  alias SakWeb.ChatLive.Command
  alias SakWeb.ChatLive.Confirm
  alias SakWeb.ChatLive.Entries
  alias SakWeb.ChatLive.Items
  alias SakWeb.ChatLive.Manage
  alias SakWeb.ChatLive.Models
  alias SakWeb.ChatLive.NewSession
  alias SakWeb.ChatLive.Search
  alias SakWeb.ChatLive.Sessions

  def handle(key, socket) do
    socket = assign(socket, last_notice: "")

    case modal(socket.assigns) do
      nil -> global(key, socket)
      modal -> modal_key(modal, key, socket)
    end
  end

  def close_help(socket) do
    assign(socket, help_open?: false, help_search: "")
  end

  def focus_pane(%{assigns: %{zoomed_pane: nil}} = socket, pane) do
    assign(socket, focused_pane: pane)
  end

  def focus_pane(socket, pane) do
    assign(socket, focused_pane: pane, zoomed_pane: pane)
  end

  defp modal(%{help_open?: true}), do: :help
  defp modal(%{models: %{}}), do: :models
  defp modal(%{new_session: %{}}), do: :wizard
  defp modal(%{confirm: %{}}), do: :confirm
  defp modal(%{rename: %{}}), do: :rename
  defp modal(%{command_open?: true}), do: :command
  defp modal(%{chat_search_open?: true}), do: :chat_search
  defp modal(%{sessions_filter_open?: true}), do: :sessions_filter
  defp modal(_assigns), do: nil

  defp modal_key(:help, "escape", socket) do
    close_help(socket)
  end

  defp modal_key(:models, "escape", socket) do
    Models.close(socket)
  end

  defp modal_key(:wizard, "escape", socket) do
    NewSession.back(socket)
  end

  defp modal_key(:confirm, "escape", socket) do
    Confirm.cancel(socket)
  end

  defp modal_key(:confirm, "enter", socket) do
    Confirm.accept(socket)
  end

  defp modal_key(:rename, "escape", socket) do
    Manage.cancel_rename(socket)
  end

  defp modal_key(:command, "escape", socket) do
    Command.close(socket)
  end

  defp modal_key(:chat_search, "escape", socket) do
    Search.close(socket)
  end

  defp modal_key(:sessions_filter, "escape", socket) do
    Sessions.close_filter(socket)
  end

  defp modal_key(_modal, _key, socket), do: socket

  defp global(":", socket) do
    Command.open(socket)
  end

  defp global("?", socket) do
    assign(socket, help_open?: true, help_search: "")
  end

  defp global("z", socket) do
    toggle_zoom(socket)
  end

  defp global("t", socket) do
    socket |> update(:thinking_visible?, &(!&1)) |> Items.refresh()
  end

  defp global("o", socket) do
    socket |> update(:tool_output_visible?, &(!&1)) |> Items.refresh()
  end

  defp global("0", socket) do
    focus_pane(socket, :chat_history)
  end

  defp global("1", socket) do
    focus_pane(socket, :sessions_and_logs)
  end

  defp global(bracket, socket) when bracket in ["[", "]"] do
    toggle_sidebar_tab(socket)
  end

  defp global(key, %{assigns: %{focused_pane: :chat_history}} = socket) do
    chat_key(key, socket)
  end

  defp global(key, %{assigns: %{sidebar_tab: :sessions}} = socket) do
    sessions_key(key, socket)
  end

  defp global(_key, socket), do: socket

  defp chat_key(key, %{assigns: %{chat_tab: :entries}} = socket) do
    entries_key(key, socket)
  end

  defp chat_key("/", socket) do
    Search.open(socket)
  end

  defp chat_key("n", socket) do
    Search.jump(socket, 1)
  end

  defp chat_key("N", socket) do
    Search.jump(socket, -1)
  end

  defp chat_key(_key, socket), do: socket

  defp entries_key(code, socket) when code in ["j", "down"] do
    Entries.move(socket, 1)
  end

  defp entries_key(code, socket) when code in ["k", "up"] do
    Entries.move(socket, -1)
  end

  defp entries_key("g", socket) do
    Entries.select_first(socket)
  end

  defp entries_key("G", socket) do
    Entries.select_last(socket)
  end

  defp entries_key("ctrl-d", socket) do
    Entries.page(socket, 1)
  end

  defp entries_key("ctrl-u", socket) do
    Entries.page(socket, -1)
  end

  defp entries_key("enter", socket) do
    Entries.toggle_detail(socket)
  end

  defp entries_key("f", socket) do
    Entries.fork(socket)
  end

  defp entries_key(_key, socket), do: socket

  defp sessions_key("n", socket) do
    NewSession.open(socket)
  end

  defp sessions_key("/", socket) do
    Sessions.open_filter(socket)
  end

  defp sessions_key("a", socket) do
    Manage.archive(socket)
  end

  defp sessions_key("R", socket) do
    Manage.restore(socket)
  end

  defp sessions_key("A", socket) do
    Sessions.toggle_archived(socket)
  end

  defp sessions_key("d", socket) do
    Manage.ask_delete(socket)
  end

  defp sessions_key("r", socket) do
    Manage.ask_rename(socket)
  end

  defp sessions_key("enter", socket) do
    open_row(socket)
  end

  defp sessions_key(code, socket) when code in ["j", "down"] do
    Sessions.move(socket, 1)
  end

  defp sessions_key(code, socket) when code in ["k", "up"] do
    Sessions.move(socket, -1)
  end

  defp sessions_key(_key, socket), do: socket

  defp open_row(%{assigns: %{focused_pane: :sessions_and_logs}} = socket) do
    case Sessions.cursor_row(socket.assigns) do
      {:session, session} -> push_patch(socket, to: ~p"/c/#{session["id"]}")
      {:header, _header} -> Sessions.toggle(socket)
      nil -> socket
    end
  end

  defp open_row(socket), do: socket

  defp toggle_sidebar_tab(%{assigns: %{focused_pane: :sessions_and_logs}} = socket) do
    update(socket, :sidebar_tab, fn
      :sessions -> :logs
      :logs -> :sessions
    end)
  end

  defp toggle_sidebar_tab(%{assigns: %{focused_pane: :chat_history}} = socket) do
    Entries.switch_tab(socket)
  end

  defp toggle_sidebar_tab(socket), do: socket

  defp toggle_zoom(%{assigns: %{zoomed_pane: nil, focused_pane: pane}} = socket) do
    assign(socket, zoomed_pane: pane)
  end

  defp toggle_zoom(socket) do
    assign(socket, zoomed_pane: nil)
  end
end
