defmodule SakWeb.ChatLive.Subagents do
  @moduledoc false

  alias Phoenix.Component
  alias Sak.SubagentRows

  def reset(socket) do
    Component.assign(socket,
      subagents: [],
      subagents_selected: 0,
      show_finished_subagents?: false
    )
  end

  def refresh(%{assigns: %{chat_tab: :subagents, current_id: id}} = socket) when is_integer(id) do
    case client().request("list_subagents", %{"conversationId" => id}) do
      {:ok, %{"subagents" => subagents}} ->
        socket |> Component.assign(subagents: subagents) |> clamp()

      {:error, reason} ->
        Component.assign(socket, last_error: reason)
    end
  end

  def refresh(socket), do: socket

  def rows(assigns), do: SubagentRows.rows(assigns.subagents, assigns.show_finished_subagents?)

  def counts(assigns), do: SubagentRows.counts(assigns.subagents)

  def move(socket, delta) do
    Component.update(socket, :subagents_selected, &(&1 + delta))
    |> clamp()
  end

  def select_index(socket, index) do
    socket |> Component.assign(subagents_selected: index) |> clamp()
  end

  def toggle_finished(socket) do
    socket
    |> Component.update(:show_finished_subagents?, &(!&1))
    |> clamp()
  end

  def abort_selected(socket) do
    case selected(socket.assigns) do
      %{live?: true, id: id} ->
        case client().request("abort", %{"conversationId" => id}) do
          {:ok, _result} -> refresh(socket)
          {:error, reason} -> Component.assign(socket, last_error: reason)
        end

      _finished_or_none ->
        socket
    end
  end

  def selected(assigns), do: Enum.at(rows(assigns), assigns.subagents_selected)

  defp clamp(socket) do
    last = max(length(rows(socket.assigns)) - 1, 0)
    Component.update(socket, :subagents_selected, &(&1 |> max(0) |> min(last)))
  end

  defp client do
    Application.get_env(:sak, :gateway_client, Sak.Gateway)
  end
end
