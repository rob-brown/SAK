defmodule Sak.Hints do
  @type hint :: {String.t(), String.t()}

  @spec for_assigns(map()) :: [hint()]
  def for_assigns(assigns) do
    cond do
      assigns.help_open? -> [{"Close", "<esc>"}]
      assigns.models != nil -> [{"Close", "<esc>"}]
      assigns.confirm_delete != nil -> [{"Delete", "<enter>"}, {"Cancel", "<esc>"}]
      assigns.rename != nil -> []
      assigns.sessions_filter_open? -> []
      assigns.new_session != nil -> []
      assigns.command_open? -> []
      assigns.chat_search_open? -> []
      true -> pane(assigns)
    end
  end

  @spec text([hint()]) :: String.t()
  def text(hints) do
    Enum.map_join(hints, " | ", fn {label, key} -> "#{label}: #{key}" end)
  end

  defp pane(%{focused_pane: :chat_history, chat_tab: :entries}) do
    [{"Details", "<enter>"}, {"Fork", "f"}, {"Chat", "["}]
  end

  defp pane(%{focused_pane: :chat_history}) do
    [
      {"Message", "<enter>"},
      {"Search", "/"},
      {"Thinking", "t"},
      {"Tool output", "o"}
    ]
  end

  defp pane(%{focused_pane: :sessions_and_logs, sidebar_tab: :logs}) do
    [{"Sessions", "["}]
  end

  defp pane(%{focused_pane: :sessions_and_logs} = assigns) do
    [{"New session", "n"}] ++
      session_row(Enum.at(assigns.session_rows, assigns.sessions_selected))
  end

  defp session_row({:header, _project}) do
    [{"Expand", "<enter>"}, {"Filter", "/"}]
  end

  defp session_row({:session, session}) do
    [
      {"Switch", "<enter>"},
      {"Rename", "r"},
      archive_hint(session),
      {"Delete", "d"},
      {"Filter", "/"}
    ]
  end

  defp session_row(nil) do
    [{"Filter", "/"}]
  end

  defp archive_hint(%{"state" => "archived"}) do
    {"Restore", "R"}
  end

  defp archive_hint(_session) do
    {"Archive", "a"}
  end
end
