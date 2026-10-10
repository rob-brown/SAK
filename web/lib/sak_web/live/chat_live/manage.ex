defmodule SakWeb.ChatLive.Manage do
  @moduledoc false

  alias Phoenix.Component
  alias SakWeb.ChatLive.Confirm
  alias SakWeb.ChatLive.Render
  alias SakWeb.ChatLive.Sessions

  def archive(socket) do
    ask(socket, "active", :archive)
  end

  def ask_delete(socket) do
    ask(socket, nil, :delete)
  end

  def restore(socket) do
    case Sessions.cursor_row(socket.assigns) do
      {:session, %{"state" => "archived"} = session} -> set_state(socket, session["id"], "active")
      _other_state_or_header -> socket
    end
  end

  def set_state(socket, id, state) do
    update_meta(socket, id, %{"state" => state})
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

  defp ask(socket, required_state, action) do
    case Sessions.cursor_row(socket.assigns) do
      {:session, session} ->
        if required_state in [nil, session["state"]] do
          Confirm.ask(socket, %{
            action: action,
            id: session["id"],
            label: Render.session_label(session),
            cwd: session["cwd"]
          })
        else
          socket
        end

      _header_or_nothing ->
        socket
    end
  end

  defp update_meta(socket, id, fields) do
    case client().request("set_meta", Map.put(fields, "conversationId", id)) do
      {:ok, _result} -> socket |> Component.assign(last_error: nil) |> Sessions.refresh()
      {:error, reason} -> Component.assign(socket, last_error: reason)
    end
  end

  defp client do
    Application.get_env(:sak, :gateway_client, Sak.Gateway)
  end
end
