defmodule SakWeb.ChatLive.Entries do
  @moduledoc false

  alias Phoenix.Component
  alias Phoenix.LiveView
  alias Sak.EntryRows
  alias SakWeb.ChatLive.Render
  alias SakWeb.ChatLive.Sessions

  @page 10

  def switch_tab(socket) do
    case socket.assigns.chat_tab do
      :chat -> socket |> Component.assign(chat_tab: :entries) |> refresh() |> select_last()
      :entries -> Component.assign(socket, chat_tab: :chat)
    end
  end

  def show(socket, "entries") do
    if socket.assigns.chat_tab == :entries do
      socket
    else
      switch_tab(socket)
    end
  end

  def show(socket, _tab) do
    Component.assign(socket, chat_tab: :chat)
  end

  def refresh(%{assigns: %{chat_tab: :entries, chat: chat}} = socket) do
    rows = EntryRows.rows(chat.records)
    last = max(length(rows) - 1, 0)

    Component.assign(socket,
      entry_rows: rows,
      entries_selected: min(socket.assigns.entries_selected, last)
    )
  end

  def refresh(socket), do: socket

  def reset(socket) do
    Component.assign(socket,
      chat_tab: :chat,
      entry_rows: [],
      entries_selected: 0,
      entries_open: MapSet.new()
    )
  end

  def move(socket, delta) do
    last = max(length(socket.assigns.entry_rows) - 1, 0)

    Component.update(socket, :entries_selected, fn selected ->
      (selected + delta) |> max(0) |> min(last)
    end)
  end

  def page(socket, direction) do
    move(socket, direction * @page)
  end

  def select_first(socket) do
    Component.assign(socket, entries_selected: 0)
  end

  def select_last(socket) do
    Component.assign(socket, entries_selected: max(length(socket.assigns.entry_rows) - 1, 0))
  end

  def select_index(socket, index) do
    Component.assign(socket, entries_selected: index)
  end

  def toggle_detail(socket) do
    case selected_row(socket.assigns) do
      nil -> socket
      row -> Component.update(socket, :entries_open, &toggle_member(&1, row.id))
    end
  end

  def fork(%{assigns: %{current_id: id}} = socket) when is_integer(id) do
    case selected_row(socket.assigns) do
      nil -> socket
      row -> fork_at(socket, id, row)
    end
  end

  def fork(socket), do: socket

  def selected_row(assigns) do
    Enum.at(assigns.entry_rows, assigns.entries_selected)
  end

  defp fork_at(socket, id, row) do
    case client().request("fork", %{"conversationId" => id, "at" => row.id}) do
      {:ok, %{"conversationId" => forked}} ->
        socket
        |> Component.assign(last_error: nil, last_notice: notice(socket.assigns, id, row))
        |> Sessions.refresh()
        |> LiveView.push_patch(to: "/c/#{forked}")

      {:error, reason} ->
        Component.assign(socket, last_error: reason)
    end
  end

  defp notice(assigns, id, row) do
    label =
      Render.session_label(Enum.find(assigns.conversations, &(&1["id"] == id)) || %{"id" => id})

    "forked #{label} at entry #{row.number} (id #{row.id})"
  end

  defp toggle_member(set, id) do
    if MapSet.member?(set, id) do
      MapSet.delete(set, id)
    else
      MapSet.put(set, id)
    end
  end

  defp client do
    Application.get_env(:sak, :gateway_client, Sak.Gateway)
  end
end
