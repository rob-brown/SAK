defmodule SakWeb.ChatLive.Command do
  @moduledoc false

  alias Phoenix.Component
  alias Phoenix.LiveView
  alias Sak.Command
  alias SakWeb.ChatLive.Models

  def open(socket) do
    socket |> Component.assign(command_open?: true) |> query("")
  end

  def query(%{assigns: %{command_open?: false}} = socket, _text), do: socket

  def query(socket, text) do
    Component.assign(socket,
      command_query: text,
      command_results: Command.filter(text),
      command_selected: 0
    )
  end

  def close(socket) do
    Component.assign(socket, command_open?: false, command_query: "", command_results: [])
  end

  def move(%{assigns: %{command_open?: false}} = socket, _delta), do: socket

  def move(socket, delta) do
    last = max(length(socket.assigns.command_results) - 1, 0)
    Component.update(socket, :command_selected, &((&1 + delta) |> max(0) |> min(last)))
  end

  def run(%{assigns: %{command_open?: false}} = socket), do: socket

  def run(socket) do
    case Enum.at(socket.assigns.command_results, socket.assigns.command_selected) do
      nil -> socket
      command -> socket |> close() |> execute(command)
    end
  end

  def run_index(socket, index) do
    socket |> Component.assign(command_selected: index) |> run()
  end

  defp execute(socket, %Command{name: "model"}) do
    Models.open(socket)
  end

  defp execute(%{assigns: %{current_id: nil}} = socket, _command) do
    Component.assign(socket, last_error: "no active session")
  end

  defp execute(socket, %Command{name: "clear"}) do
    cwd = current_cwd(socket.assigns)

    case client().request("create_conversation", %{"cwd" => cwd}) do
      {:ok, %{"conversationId" => id}} -> LiveView.push_patch(socket, to: "/c/#{id}")
      {:error, reason} -> Component.assign(socket, last_error: reason)
    end
  end

  defp current_cwd(assigns) do
    case Enum.find(assigns.conversations, &(&1["id"] == assigns.current_id)) do
      %{"cwd" => cwd} when is_binary(cwd) -> cwd
      _unknown -> assigns.default_cwd
    end
  end

  defp client do
    Application.get_env(:sak, :gateway_client, Sak.Gateway)
  end
end
