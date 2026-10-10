defmodule SakWeb.ChatLive.Confirm do
  @moduledoc false

  alias Phoenix.Component
  alias Phoenix.LiveView
  alias SakWeb.ChatLive.Entries
  alias SakWeb.ChatLive.Manage

  def ask(socket, confirm) do
    Component.assign(socket, confirm: confirm)
  end

  def accept(%{assigns: %{confirm: confirm}} = socket) when is_map(confirm) do
    socket |> Component.assign(confirm: nil) |> run(confirm)
  end

  def accept(socket), do: socket

  def cancel(socket) do
    Component.assign(socket, confirm: nil)
  end

  defp run(socket, %{action: :archive, id: id}) do
    Manage.set_state(socket, id, "archived")
  end

  defp run(socket, %{action: :delete, id: id}) do
    socket |> Manage.set_state(id, "deleted") |> leave_if_open(id)
  end

  defp run(socket, %{action: :fork, id: id, row: row}) do
    Entries.fork_at(socket, id, row)
  end

  defp leave_if_open(%{assigns: %{current_id: id}} = socket, id) do
    LiveView.push_patch(socket, to: "/")
  end

  defp leave_if_open(socket, _id), do: socket
end
