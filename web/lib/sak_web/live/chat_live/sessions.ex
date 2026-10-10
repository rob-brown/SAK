defmodule SakWeb.ChatLive.Sessions do
  @moduledoc false

  alias Phoenix.Component
  alias Sak.SessionRows

  def rebuild(socket) do
    assigns = socket.assigns
    previous = assigns.session_rows |> Enum.at(assigns.sessions_selected) |> SessionRows.row_key()

    {rows, labels} =
      SessionRows.build(assigns.conversations, assigns.project_labels,
        collapsed: assigns.collapsed_projects
      )

    Component.assign(socket,
      session_rows: rows,
      project_labels: labels,
      sessions_selected: cursor_after(rows, previous, assigns.sessions_selected)
    )
  end

  def move(socket, delta) do
    last = max(length(socket.assigns.session_rows) - 1, 0)

    Component.update(socket, :sessions_selected, fn selected ->
      (selected + delta) |> max(0) |> min(last)
    end)
  end

  def move_to(socket, index) do
    move(socket, index - socket.assigns.sessions_selected)
  end

  def toggle(socket) do
    case cursor_row(socket.assigns) do
      {:header, header} ->
        socket
        |> Component.update(:collapsed_projects, &toggle_member(&1, header.label))
        |> rebuild()

      _session_or_nothing ->
        socket
    end
  end

  def toggle_at(socket, index) do
    socket |> move_to(index) |> toggle()
  end

  def cursor_row(%{session_rows: rows, sessions_selected: index}) do
    Enum.at(rows, index)
  end

  def cursor_cwd(assigns) do
    case cursor_row(assigns) do
      {:header, header} -> header.path
      {:session, session} -> session["cwd"]
      nil -> nil
    end
  end

  def cwd_of(conversations, id) do
    case Enum.find(conversations, &(&1["id"] == id)) do
      %{"cwd" => cwd} -> cwd
      nil -> nil
    end
  end

  defp toggle_member(set, label) do
    if MapSet.member?(set, label) do
      MapSet.delete(set, label)
    else
      MapSet.put(set, label)
    end
  end

  defp cursor_after(rows, previous_key, previous_index) do
    case SessionRows.index_of(rows, previous_key) do
      nil -> previous_index |> min(max(length(rows) - 1, 0)) |> max(0)
      index -> index
    end
  end
end
