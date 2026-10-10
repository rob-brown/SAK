defmodule SakWeb.ChatLive.Render do
  @moduledoc false

  alias Sak.Chat
  alias Sak.Help
  alias Sak.NewSessionWizard
  alias SakWeb.ChatLive.Mention

  def pane_classes(focused_pane, pane, zoomed_pane \\ nil) do
    border = if focused_pane == pane, do: "border-yellow-600", else: "border-neutral-800"
    display = if zoomed_pane in [nil, pane], do: "flex flex-col", else: "hidden"
    "rounded-md border #{border} #{display} min-h-0 overflow-hidden"
  end

  def sidebar_classes(nil), do: "w-72 shrink-0 flex flex-col gap-2 min-h-0"
  def sidebar_classes(:chat_history), do: "hidden"
  def sidebar_classes(_zoomed_pane), do: "flex-1 min-w-0 flex flex-col gap-2 min-h-0"

  def entry_row_classes(selected?) do
    [
      "px-2 py-0.5 flex gap-2 items-baseline cursor-pointer hover:bg-neutral-900",
      selected? && "bg-neutral-800 ring-1 ring-inset ring-neutral-500"
    ]
  end

  def entry_label_class("user"), do: "text-white"
  def entry_label_class("assistant"), do: "text-green-400"
  def entry_label_class("tool"), do: "text-fuchsia-400"
  def entry_label_class("system"), do: "text-yellow-600"
  def entry_label_class(_label), do: "text-neutral-400"

  def header_classes(index, selected_index) do
    [
      "px-2 pt-2 pb-1 flex gap-2 items-baseline text-blue-400 font-semibold cursor-pointer",
      index == selected_index && "ring-1 ring-inset ring-neutral-500"
    ]
  end

  def session_row_classes(current_id, session, index, selected_index) do
    [
      "px-2 py-1 cursor-pointer hover:bg-neutral-900 flex gap-2 items-baseline",
      session["id"] == current_id && "bg-neutral-800",
      index == selected_index && "ring-1 ring-inset ring-neutral-500"
    ]
  end

  def session_label(%{"name" => name}) when is_binary(name) and name != "", do: name

  def session_label(session) do
    "##{session["id"]}"
  end

  def model_label(%{"model" => model}) when is_binary(model) do
    case String.split(model, "/", parts: 2) do
      [_provider, rest] -> rest
      [only] -> only
    end
  end

  def model_label(_session), do: ""

  def disclosure(%{collapsed?: true}), do: "▸"
  def disclosure(%{collapsed?: false}), do: "▾"

  def header_label(%{label: ""}, _home), do: "no directory"

  def header_label(%{label: label}, home) do
    NewSessionWizard.tilde(label, home)
  end

  def status_glyph(session, current_id, chat) do
    glyph(running_here?(session, current_id, chat))
  end

  def status_glyph_class(session, current_id, chat) do
    glyph_class(running_here?(session, current_id, chat))
  end

  defp running_here?(session, current_id, chat) do
    session["id"] == current_id and chat.running?
  end

  defp glyph(true), do: "●"
  defp glyph(false), do: " "

  defp glyph_class(true), do: "text-cyan-400 font-bold"
  defp glyph_class(false), do: "text-transparent"

  def help_tab(%{focused_pane: :chat_history, chat_tab: tab}), do: tab
  def help_tab(%{sidebar_tab: tab}), do: tab

  def help_rows(focused_pane, sidebar_tab, raw_query) do
    Help.rows(focused_pane, sidebar_tab, Help.parse_query(raw_query))
  end

  def conversation_model(%{agent: %{"model" => %{"provider" => provider, "modelId" => id}}}) do
    "#{provider}/#{id}"
  end

  def conversation_model(_chat), do: nil

  def mention_results(assigns) do
    Mention.results(assigns)
  end

  def status_line(error, _notice, _id, _chat) when is_binary(error) do
    "error: #{error}"
  end

  def status_line(_error, notice, _id, _chat) when notice != "", do: notice
  def status_line(_error, _notice, nil, _chat), do: ""

  def status_line(_error, _notice, _id, %Chat{failure: failure}) when is_binary(failure) do
    "failed: #{failure}"
  end

  def status_line(_error, _notice, id, %Chat{running?: true, running_tools: tools})
      when map_size(tools) > 0 do
    "running #{tools |> Map.values() |> Enum.join(", ")} in #{id}…"
  end

  def status_line(_error, _notice, id, %Chat{running?: true}) do
    "waiting for a reply from #{id}…"
  end

  def status_line(_error, _notice, id, chat) do
    model = get_in(chat.agent, ["model", "modelId"]) || "idle"
    "active session: #{id} · #{model} · #{Chat.total_tokens(chat)} tokens"
  end
end
