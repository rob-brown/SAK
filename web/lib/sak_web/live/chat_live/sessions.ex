defmodule SakWeb.ChatLive.Sessions do
  @moduledoc false

  alias Phoenix.Component
  alias Sak.SessionRows

  def refresh(socket) do
    case client().request("list_conversations", %{}) do
      {:ok, %{"conversations" => conversations}} ->
        socket
        |> Component.assign(conversations: Enum.sort_by(conversations, & &1["id"], :desc))
        |> rebuild()

      {:error, reason} ->
        Component.assign(socket, last_error: reason)
    end
  end

  def rebuild(socket) do
    assigns = socket.assigns
    previous = assigns.session_rows |> Enum.at(assigns.sessions_selected) |> SessionRows.row_key()

    {rows, labels} =
      SessionRows.build(visible(assigns), assigns.project_labels,
        collapsed: assigns.collapsed_projects
      )

    Component.assign(socket,
      session_rows: rows,
      project_labels: labels,
      sessions_selected: cursor_after(rows, previous, assigns.sessions_selected)
    )
  end

  def visible(assigns) do
    assigns.conversations
    |> Enum.filter(&shown?(&1, assigns.show_archived?))
    |> Enum.filter(&matches?(&1, assigns.sessions_filter))
  end

  def toggle_archived(socket) do
    socket |> Component.update(:show_archived?, &(!&1)) |> rebuild()
  end

  def open_filter(socket) do
    Component.assign(socket, sessions_filter_open?: true)
  end

  def change_filter(socket, term) do
    socket |> Component.assign(sessions_filter: term, sessions_selected: 0) |> rebuild()
  end

  def confirm_filter(socket) do
    Component.assign(socket, sessions_filter_open?: false)
  end

  def close_filter(socket) do
    socket
    |> Component.assign(sessions_filter_open?: false, sessions_filter: "", sessions_selected: 0)
    |> rebuild()
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

  defp shown?(%{"state" => "archived"}, show_archived?), do: show_archived?
  defp shown?(_conversation, _show_archived?), do: true

  defp matches?(_conversation, ""), do: true

  defp matches?(conversation, term) do
    haystack =
      [conversation["name"], conversation["cwd"], conversation["model"]]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")
      |> String.downcase()

    String.contains?(haystack, String.downcase(term))
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

  defp client do
    Application.get_env(:sak, :gateway_client, Sak.Gateway)
  end
end
