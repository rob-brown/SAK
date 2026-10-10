defmodule SakWeb.ChatLive.Manage do
  @moduledoc false

  alias Phoenix.Component
  alias Phoenix.LiveView
  alias SakWeb.ChatLive.Render
  alias SakWeb.ChatLive.Sessions

  def archive(socket) do
    change_state(socket, "active", "archived")
  end

  def restore(socket) do
    change_state(socket, "archived", "active")
  end

  def ask_delete(socket) do
    case Sessions.cursor_row(socket.assigns) do
      {:session, session} ->
        Component.assign(socket,
          confirm_delete: %{
            id: session["id"],
            label: Render.session_label(session),
            cwd: session["cwd"]
          }
        )

      _header_or_nothing ->
        socket
    end
  end

  def confirm_delete(%{assigns: %{confirm_delete: %{id: id}}} = socket) do
    socket
    |> Component.assign(confirm_delete: nil)
    |> update_meta(id, %{"state" => "deleted"})
    |> leave_if_open(id)
  end

  def confirm_delete(socket), do: socket

  def cancel_delete(socket) do
    Component.assign(socket, confirm_delete: nil)
  end

  def ask_rename(socket) do
    case Sessions.cursor_row(socket.assigns) do
      {:session, session} ->
        Component.assign(socket, rename: %{id: session["id"], name: session["name"] || ""})

      _header_or_nothing ->
        socket
    end
  end

  def save_rename(%{assigns: %{rename: %{id: id}}} = socket, name) do
    socket |> Component.assign(rename: nil) |> update_meta(id, %{"name" => String.trim(name)})
  end

  def save_rename(socket, _name), do: socket

  def cancel_rename(socket) do
    Component.assign(socket, rename: nil)
  end

  defp change_state(socket, from, to) do
    case Sessions.cursor_row(socket.assigns) do
      {:session, %{"state" => ^from} = session} ->
        update_meta(socket, session["id"], %{"state" => to})

      _other_state_or_header ->
        socket
    end
  end

  defp update_meta(socket, id, fields) do
    case client().request("set_meta", Map.put(fields, "conversationId", id)) do
      {:ok, _result} -> socket |> Component.assign(last_error: nil) |> Sessions.refresh()
      {:error, reason} -> Component.assign(socket, last_error: reason)
    end
  end

  defp leave_if_open(%{assigns: %{current_id: id}} = socket, id) do
    LiveView.push_patch(socket, to: "/")
  end

  defp leave_if_open(socket, _id), do: socket

  defp client do
    Application.get_env(:sak, :gateway_client, Sak.Gateway)
  end
end
