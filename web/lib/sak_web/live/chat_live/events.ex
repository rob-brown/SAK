defmodule SakWeb.ChatLive.Events do
  @moduledoc false

  import Phoenix.Component, only: [assign: 2]

  alias SakWeb.ChatLive.Command
  alias SakWeb.ChatLive.Confirm
  alias SakWeb.ChatLive.Keys
  alias SakWeb.ChatLive.Manage
  alias SakWeb.ChatLive.Mention
  alias SakWeb.ChatLive.Models
  alias SakWeb.ChatLive.NewSession
  alias SakWeb.ChatLive.Permission
  alias SakWeb.ChatLive.PermissionMode
  alias SakWeb.ChatLive.Search
  alias SakWeb.ChatLive.Sessions
  alias SakWeb.ChatLive.Subagents
  alias SakWeb.ChatLive.UsagePanel

  def handle("wizard_query", %{"query" => query}, socket) do
    NewSession.set_query(socket, query)
  end

  def handle("wizard_move", %{"delta" => delta}, socket) do
    NewSession.move(socket, delta)
  end

  def handle("wizard_accept", _params, socket) do
    NewSession.accept(socket)
  end

  def handle("wizard_back", _params, socket) do
    NewSession.back(socket)
  end

  def handle("wizard_select_index", %{"index" => index}, socket) do
    NewSession.select_index(socket, String.to_integer(index))
  end

  def handle("models_search", %{"query" => query}, socket) do
    Models.search(socket, query)
  end

  def handle("models_move", %{"delta" => delta}, socket) do
    Models.move(socket, delta)
  end

  def handle("models_pick", _params, socket) do
    Models.pick(socket)
  end

  def handle("models_pick_index", %{"index" => index}, socket) do
    Models.pick_index(socket, String.to_integer(index))
  end

  def handle("close_models", _params, socket) do
    Models.close(socket)
  end

  def handle("help_search", %{"query" => query}, socket) do
    assign(socket, help_search: query)
  end

  def handle("close_help", _params, socket) do
    Keys.close_help(socket)
  end

  def handle("chat_search_change", %{"term" => term}, socket) do
    Search.change(socket, term)
  end

  def handle("chat_search_next", _params, socket) do
    Search.confirm(socket)
  end

  def handle("close_chat_search", _params, socket) do
    Search.close(socket)
  end

  def handle("sessions_filter_change", %{"term" => term}, socket) do
    Sessions.change_filter(socket, term)
  end

  def handle("sessions_filter_confirm", _params, socket) do
    Sessions.confirm_filter(socket)
  end

  def handle("close_usage", _params, socket) do
    UsagePanel.close(socket)
  end

  def handle("mode_pick_index", %{"index" => index}, socket) do
    PermissionMode.pick_index(socket, String.to_integer(index))
  end

  def handle("close_mode_picker", _params, socket) do
    PermissionMode.close(socket)
  end

  def handle("subagent_select", %{"index" => index}, socket) do
    Subagents.select_index(socket, String.to_integer(index))
  end

  def handle("subagent_abort", _params, socket) do
    Subagents.abort_selected(socket)
  end

  def handle("permission_answer", %{"approval" => approval}, socket) do
    Permission.answer(socket, approval)
  end

  def handle("confirm_accept", _params, socket) do
    Confirm.accept(socket)
  end

  def handle("confirm_cancel", _params, socket) do
    Confirm.cancel(socket)
  end

  def handle("rename_save", %{"name" => name}, socket) do
    Manage.save_rename(socket, name)
  end

  def handle("mention_query", %{"query" => query}, socket) do
    Mention.query(socket, query)
  end

  def handle("mention_close", _params, socket) do
    Mention.close(socket)
  end

  def handle("mention_move", %{"delta" => delta}, socket) do
    Mention.move(socket, delta)
  end

  def handle("mention_select", _params, socket) do
    Mention.select(socket)
  end

  def handle("mention_select_index", %{"index" => index}, socket) do
    Mention.select_index(socket, String.to_integer(index))
  end

  def handle("command_open", _params, socket) do
    Command.open(socket)
  end

  def handle("command_query", %{"query" => query}, socket) do
    Command.query(socket, query)
  end

  def handle("command_close", _params, socket) do
    Command.close(socket)
  end

  def handle("command_move", %{"delta" => delta}, socket) do
    Command.move(socket, delta)
  end

  def handle("command_run", _params, socket) do
    Command.run(socket)
  end

  def handle("command_run_index", %{"index" => index}, socket) do
    Command.run_index(socket, String.to_integer(index))
  end
end
