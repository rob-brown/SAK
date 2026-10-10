defmodule SakWeb.ChatLive.Search do
  @moduledoc false

  alias Phoenix.Component
  alias Phoenix.LiveView
  alias Sak.Chat
  alias Sak.ChatSearch
  alias SakWeb.ChatLive.Items

  def open(socket) do
    Component.assign(socket,
      chat_search_open?: true,
      chat_search_term: "",
      chat_search_match_index: nil
    )
  end

  def close(socket) do
    socket
    |> Component.assign(
      chat_search_open?: false,
      chat_search_term: "",
      chat_search_match_index: nil
    )
    |> Items.refresh()
  end

  def change(socket, term) do
    socket
    |> Component.assign(chat_search_term: term, chat_search_match_index: nil)
    |> Items.refresh()
  end

  def confirm(socket) do
    socket |> jump(1) |> Component.assign(chat_search_open?: false)
  end

  def jump(%{assigns: %{chat_search_term: term}} = socket, _direction) when term in [nil, ""] do
    socket
  end

  def jump(socket, direction) do
    matches = matches(socket.assigns)
    index = ChatSearch.jump(matches, socket.assigns.chat_search_match_index, direction)

    socket
    |> Component.assign(chat_search_match_index: index)
    |> Items.refresh()
    |> LiveView.push_event("scroll_to_match", %{})
  end

  def summary(assigns) do
    matches = matches(assigns)

    current =
      if assigns.chat_search_match_index, do: Enum.at(matches, assigns.chat_search_match_index)

    {current, length(matches)}
  end

  def count_label(_index, 0), do: "no matches"
  def count_label(nil, 1), do: "1 match"
  def count_label(nil, count), do: "#{count} matches"
  def count_label(index, count), do: "#{index + 1} of #{count}"

  defp matches(assigns) do
    ChatSearch.matches(
      Chat.items(assigns.chat),
      assigns.chat_search_term,
      Items.visibility(assigns)
    )
  end
end
