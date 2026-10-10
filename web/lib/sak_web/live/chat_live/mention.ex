defmodule SakWeb.ChatLive.Mention do
  @moduledoc false

  alias Phoenix.Component
  alias Phoenix.LiveView
  alias Sak.FileIndex
  alias Sak.FilePickerQuery
  alias SakWeb.ChatLive.Sessions

  def query(%{assigns: %{mention_open?: false}} = socket, text) do
    cwd = base_cwd(socket.assigns)
    token = socket.assigns.mention_index_token + 1
    start_index(cwd, token)

    Component.assign(socket,
      mention_open?: true,
      mention_query: text,
      mention_selected: 0,
      mention_base_cwd: cwd,
      mention_root: cwd,
      mention_files: [],
      mention_loading?: true,
      mention_index_token: token
    )
  end

  def query(socket, text) do
    {root, _remainder, _label} = FilePickerQuery.resolve(socket.assigns.mention_base_cwd, text)

    socket =
      if root == socket.assigns.mention_root do
        socket
      else
        token = socket.assigns.mention_index_token + 1
        start_index(root, token)

        Component.assign(socket,
          mention_root: root,
          mention_loading?: true,
          mention_index_token: token
        )
      end

    Component.assign(socket, mention_query: text, mention_selected: 0)
  end

  def close(socket) do
    Component.assign(socket, mention_open?: false)
  end

  def move(%{assigns: %{mention_open?: false}} = socket, _delta), do: socket

  def move(socket, delta) do
    {_label, matches} = results(socket.assigns)
    last = max(length(matches) - 1, 0)
    Component.update(socket, :mention_selected, &((&1 + delta) |> max(0) |> min(last)))
  end

  def select(%{assigns: %{mention_open?: false}} = socket), do: socket

  def select(socket) do
    select_index(socket, socket.assigns.mention_selected)
  end

  def select_index(%{assigns: %{mention_open?: false}} = socket, _index), do: socket

  def select_index(socket, index) do
    {_label, matches} = results(socket.assigns)
    select_match(socket, Enum.at(matches, index))
  end

  def receive_index(%{assigns: %{mention_index_token: token}} = socket, token, files) do
    Component.assign(socket, mention_files: files, mention_loading?: false)
  end

  def receive_index(socket, _token, _files), do: socket

  def results(%{mention_base_cwd: nil}) do
    {"", []}
  end

  def results(assigns) do
    %{mention_base_cwd: cwd, mention_query: query, mention_files: files} = assigns
    FilePickerQuery.results(cwd, query, files, FilePickerQuery.picker_limit())
  end

  defp select_match(socket, nil), do: socket

  defp select_match(socket, path) do
    text = "@" <> Path.join(socket.assigns.mention_root, path) <> " "
    socket |> LiveView.push_event("mention_insert", %{text: text}) |> close()
  end

  defp start_index(root, token) do
    liveview = self()
    Task.start(fn -> send(liveview, {:mention_index, token, FileIndex.list(root)}) end)
  end

  defp base_cwd(assigns) do
    Sessions.cwd_of(assigns.conversations, assigns.current_id) || assigns.default_cwd
  end
end
