defmodule SakWeb.ChatLive.UsagePanel do
  @moduledoc false

  alias Phoenix.Component
  alias Sak.Usage

  def open(%{assigns: %{current_id: nil}} = socket) do
    Component.assign(socket, last_error: "no active session")
  end

  def open(%{assigns: %{chat: chat, current_id: id}} = socket) do
    Component.assign(socket, usage: %{id: id, summary: Usage.summarize(chat.records)})
  end

  def close(socket), do: Component.assign(socket, usage: nil)
end
