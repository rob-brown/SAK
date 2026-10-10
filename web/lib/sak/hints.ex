defmodule Sak.Hints do
  @type hint :: {String.t(), String.t()}

  @spec for_assigns(map()) :: [hint()]
  def for_assigns(assigns) do
    cond do
      assigns.help_open? -> [{"Close", "<esc>"}]
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

  defp session_row({:header, _project}), do: [{"Expand", "<enter>"}]
  defp session_row({:session, _session}), do: [{"Switch", "<enter>"}]
  defp session_row(nil), do: []
end
