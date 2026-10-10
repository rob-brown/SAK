defmodule SakWeb.ChatLive.NewSession do
  @moduledoc false

  alias Phoenix.Component
  alias Phoenix.LiveView
  alias Sak.FileIndex
  alias Sak.NewSessionWizard
  alias SakWeb.ChatLive.Sessions

  @index_limit 5_000

  def open(socket) do
    assigns = socket.assigns

    hints =
      [
        cursor_cwd: Sessions.cursor_cwd(assigns),
        active_cwd: Sessions.cwd_of(assigns.conversations, assigns.current_id),
        home: assigns.home
      ] ++ model_hints()

    projects =
      assigns.conversations |> Enum.map(& &1["cwd"]) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    wizard = NewSessionWizard.new(assigns.default_cwd, projects, hints)

    socket
    |> Component.assign(new_session: %{phase: :ready, wizard: wizard, error: nil})
    |> update_wizard(wizard)
  end

  def close(socket) do
    Component.assign(socket, new_session: nil)
  end

  def index_received(%{assigns: %{new_session: %{wizard: wizard}}} = socket, root, directories) do
    put(socket, %{wizard: NewSessionWizard.directories_loaded(wizard, root, directories)})
  end

  def index_received(socket, _root, _directories), do: socket

  def set_query(%{assigns: %{new_session: %{phase: :ready, wizard: wizard}}} = socket, query) do
    update_wizard(socket, NewSessionWizard.set_query(wizard, query))
  end

  def set_query(socket, _query), do: socket

  def move(%{assigns: %{new_session: %{phase: :ready, wizard: wizard}}} = socket, delta) do
    put(socket, %{wizard: NewSessionWizard.move(wizard, delta)})
  end

  def move(socket, _delta), do: socket

  def select_index(%{assigns: %{new_session: %{phase: :ready, wizard: wizard}}} = socket, index) do
    socket |> put(%{wizard: NewSessionWizard.move(wizard, index - wizard.selected)}) |> accept()
  end

  def select_index(socket, _index), do: socket

  def accept(%{assigns: %{new_session: %{phase: :ready, wizard: wizard}}} = socket) do
    case NewSessionWizard.accept(wizard) do
      :none -> socket
      {:next, next} -> update_wizard(socket, next)
      {:done, answers} -> submit(socket, answers)
    end
  end

  def accept(socket), do: socket

  def back(%{assigns: %{new_session: %{wizard: wizard}}} = socket) do
    case NewSessionWizard.back(wizard) do
      :cancel -> close(socket)
      {:ok, previous} -> update_wizard(socket, previous)
    end
  end

  def back(socket) do
    close(socket)
  end

  defp model_hints do
    case client().request("list_models", %{}) do
      {:ok, %{"models" => models, "current" => current}} ->
        [models: models, default_model: current["modelId"]]

      _unavailable ->
        []
    end
  end

  defp submit(socket, answers) do
    params =
      %{"cwd" => answers.cwd}
      |> put_present("modelId", answers.model_id)
      |> put_present("name", answers.name)

    case client().request("create_conversation", params) do
      {:ok, %{"conversationId" => id}} ->
        socket |> close() |> Sessions.refresh() |> LiveView.push_patch(to: "/c/#{id}")

      {:error, reason} ->
        put(socket, %{error: reason})
    end
  end

  defp put_present(params, _key, nil), do: params
  defp put_present(params, _key, ""), do: params

  defp put_present(params, key, value) do
    Map.put(params, key, value)
  end

  defp update_wizard(socket, wizard) do
    {wizard, root} = NewSessionWizard.request_index(wizard)
    start_index(socket, root)
    put(socket, %{wizard: wizard, error: nil})
  end

  defp put(socket, changes) do
    Component.update(socket, :new_session, &Map.merge(&1, changes))
  end

  defp start_index(_socket, nil), do: :ok

  defp start_index(socket, root) do
    liveview = self()
    home = socket.assigns.home

    Task.start(fn ->
      directories = FileIndex.list(root, kind: :directories, home: home, limit: @index_limit)
      send(liveview, {:wizard_index, root, directories})
    end)

    :ok
  end

  defp client do
    Application.get_env(:sak, :gateway_client, Sak.Gateway)
  end
end
