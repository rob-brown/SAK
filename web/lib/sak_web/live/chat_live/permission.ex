defmodule SakWeb.ChatLive.Permission do
  @moduledoc false

  alias Phoenix.Component

  @approvals %{"y" => "allow", "a" => "allow_conversation", "n" => "deny", "escape" => "deny"}

  def keys, do: Map.keys(@approvals)

  def received(socket, request) do
    pending = socket.assigns.permissions

    if Enum.any?(pending, &(&1["requestId"] == request["requestId"])) do
      socket
    else
      Component.assign(socket, permissions: pending ++ [request])
    end
  end

  def resolved(socket, request_id) do
    pending = Enum.reject(socket.assigns.permissions, &(&1["requestId"] == request_id))
    Component.assign(socket, permissions: pending)
  end

  def reset(socket), do: Component.assign(socket, permissions: [])

  def key(%{assigns: %{permissions: [_ | _]}} = socket, key) do
    case Map.fetch(@approvals, key) do
      {:ok, approval} -> answer(socket, approval)
      :error -> socket
    end
  end

  def key(socket, _key), do: socket

  def answer(%{assigns: %{permissions: [request | _]}} = socket, approval) do
    params = %{"requestId" => request["requestId"], "approval" => approval}

    case client().request("permission_reply", params) do
      {:ok, _result} ->
        socket |> resolved(request["requestId"]) |> Component.assign(last_error: nil)

      {:error, reason} ->
        Component.assign(socket, last_error: reason)
    end
  end

  def answer(socket, _approval), do: socket

  defp client do
    Application.get_env(:sak, :gateway_client, Sak.Gateway)
  end
end
