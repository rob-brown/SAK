defmodule SakWeb.ChatLive.PermissionMode do
  @moduledoc false

  alias Phoenix.Component

  def refresh(%{assigns: %{current_id: id}} = socket) when is_integer(id) do
    case client().request("permission_mode", %{"conversationId" => id}) do
      {:ok, %{"mode" => mode}} -> Component.assign(socket, permission_mode: mode)
      _unavailable -> Component.assign(socket, permission_mode: nil)
    end
  end

  def refresh(socket), do: Component.assign(socket, permission_mode: nil)

  def open(%{assigns: %{current_id: id}} = socket) when is_integer(id) do
    case client().request("permission_mode", %{"conversationId" => id}) do
      {:ok, %{"mode" => mode, "default" => default, "modes" => modes}} ->
        picker = %{
          modes: modes,
          selected: Enum.find_index(modes, &(&1 == mode)) || 0,
          current: mode,
          default: default
        }

        Component.assign(socket, mode_picker: picker, permission_mode: mode, last_error: nil)

      {:error, reason} ->
        Component.assign(socket, last_error: reason)
    end
  end

  def open(socket), do: Component.assign(socket, last_error: "no active session")

  def move(%{assigns: %{mode_picker: picker}} = socket, delta) when is_map(picker) do
    last = length(picker.modes) - 1
    selected = (picker.selected + delta) |> max(0) |> min(last)
    Component.assign(socket, mode_picker: %{picker | selected: selected})
  end

  def move(socket, _delta), do: socket

  def pick_index(%{assigns: %{mode_picker: picker}} = socket, index) when is_map(picker) do
    socket |> Component.assign(mode_picker: %{picker | selected: index}) |> pick()
  end

  def pick_index(socket, _index), do: socket

  def pick(%{assigns: %{mode_picker: picker, current_id: id}} = socket) when is_map(picker) do
    mode = Enum.at(picker.modes, picker.selected)

    case client().request("permission_mode", %{"conversationId" => id, "mode" => mode}) do
      {:ok, %{"mode" => applied}} ->
        Component.assign(socket,
          mode_picker: nil,
          permission_mode: applied,
          last_error: nil,
          last_notice: "permissions for session #{id}: #{applied}"
        )

      {:error, reason} ->
        Component.assign(socket, last_error: reason)
    end
  end

  def pick(socket), do: socket

  def close(socket), do: Component.assign(socket, mode_picker: nil)

  defp client do
    Application.get_env(:sak, :gateway_client, Sak.Gateway)
  end
end
