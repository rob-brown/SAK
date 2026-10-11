defmodule SakWeb.ChatLive.Items do
  @moduledoc false

  alias Phoenix.LiveView
  alias Sak.Chat

  def refresh(socket) do
    LiveView.stream(socket, :messages, Chat.items(socket.assigns.chat), reset: true)
  end

  def visibility(assigns) do
    %{
      thinking_visible?: assigns.thinking_visible?,
      tool_output_visible?: assigns.tool_output_visible?,
      stats_visible?: assigns.stats_visible?
    }
  end
end
