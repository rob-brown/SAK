defmodule Sak.Keybindings do
  @type entry :: {key :: String.t(), description :: String.t()}

  @spec local(atom(), atom() | nil) :: [entry()]
  def local(:chat_history, _sidebar_tab) do
    [
      {"j", "Scroll one line down"},
      {"down", "Scroll one line down"},
      {"k", "Scroll one line up"},
      {"up", "Scroll one line up"},
      {"ctrl-d", "Scroll half a page down"},
      {"ctrl-u", "Scroll half a page up"},
      {"g", "Jump to the oldest message"},
      {"G", "Jump to the most recent message"},
      {"enter", "Focus the message box"},
      {"/", "Search the chat history"},
      {"n", "Jump to the next chat search match, starting from the most recent message"},
      {"N", "Jump to the previous chat search match"}
    ]
  end

  def local(:sessions_and_logs, :sessions) do
    [
      {"[", "Switch to the previous tab"},
      {"]", "Switch to the next tab"},
      {"n", "Start a new session: choose a directory (enter accepts the default)"},
      {"j", "Move the selection down"},
      {"down", "Move the selection down"},
      {"k", "Move the selection up"},
      {"up", "Move the selection up"},
      {"enter", "Switch to the selected session, or expand or collapse the selected project"},
      {"/", "Filter the sessions by name, directory or model"},
      {"r", "Rename the selected session"},
      {"a", "Archive the selected session, or unarchive it when it is archived"},
      {"A", "Show or hide archived sessions"},
      {"d", "Delete the selected session (it is hidden for good, with a confirmation first)"}
    ]
  end

  def local(:sessions_and_logs, :logs) do
    [
      {"[", "Switch to the previous tab"},
      {"]", "Switch to the next tab"}
    ]
  end

  @spec pane_focus_entries() :: [entry()]
  def pane_focus_entries do
    [
      {"0", "Focus pane 0"},
      {"1", "Focus pane 1"}
    ]
  end

  @spec global() :: [entry()]
  def global do
    [
      {"?", "Open this help overlay"},
      {":", "Open the command popup (also from an empty message box)"},
      {"z", "Zoom the focused pane to fill the window, or restore the normal layout"},
      {"t",
       "Show or hide model thinking (reasoning) in the chat history — hidden thinking is not searchable"},
      {"o", "Show or hide full tool call output in the chat history"},
      {"scroll up", "Scroll the chat history pane up with the mouse wheel"},
      {"scroll down", "Scroll the chat history pane down with the mouse wheel"}
    ]
  end
end
