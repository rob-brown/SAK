defmodule Sak.Chat do
  @moduledoc """
  Pure model of one conversation built from the gateway's `watchEvents`
  snapshot and event batches.

  `apply_events/2` returns the new state plus stream operations for the
  LiveView: `{:insert, item}`, `{:delete, item}` and `:reset`.
  """

  defstruct entries: [],
            live: nil,
            running?: false,
            running_tools: %{},
            usage: %{},
            agent: %{},
            failure: nil

  @live_id "live"

  def live_id, do: @live_id

  def from_snapshot(snapshot) do
    entries =
      snapshot |> Map.get("entries", []) |> Enum.flat_map(&entry_items/1) |> index_items(0)

    %__MODULE__{
      entries: entries,
      live: live_item(Map.get(snapshot, "generation"), length(entries)),
      running?: Map.get(snapshot, "run") != nil,
      usage: Map.get(snapshot, "usage", %{}),
      agent: Map.get(snapshot, "agent", %{})
    }
  end

  def total_tokens(%__MODULE__{usage: usage}) do
    usage
    |> Map.get("models", %{})
    |> Map.values()
    |> Enum.map(&Map.get(&1, "totalTokens", 0))
    |> Enum.sum()
  end

  def items(%__MODULE__{} = chat) do
    chat.entries ++ List.wrap(chat.live)
  end

  def apply_events(chat, events) do
    Enum.reduce(events, {chat, []}, fn event, {chat, ops} ->
      {chat, new_ops} = apply_event(chat, event)
      {chat, ops ++ new_ops}
    end)
  end

  defp apply_event(_chat, %{"type" => "snapshot"} = snapshot) do
    {from_snapshot(snapshot), [:reset]}
  end

  defp apply_event(chat, %{
         "type" => "message_start",
         "message" => %{"role" => "assistant"} = message
       }) do
    live = live_item(%{"message" => message}, length(chat.entries))
    {%{chat | live: live}, [{:insert, live}]}
  end

  defp apply_event(%{live: nil} = chat, %{"type" => "message_update"}) do
    {chat, []}
  end

  defp apply_event(chat, %{"type" => "message_update", "changes" => changes}) do
    live = %{chat.live | blocks: Enum.reduce(changes, chat.live.blocks, &apply_change/2)}
    {%{chat | live: live}, [{:insert, live}]}
  end

  defp apply_event(chat, %{"type" => "message_end", "entry" => entry}) do
    items = entry |> entry_items() |> index_items(length(chat.entries))
    replaces_live? = Enum.any?(items, &(&1.role == :assistant))
    {live, deleted} = settle_live(chat.live, replaces_live?)
    inserted = Enum.map(items, &{:insert, &1})
    {%{chat | live: live, entries: chat.entries ++ items}, deleted ++ inserted}
  end

  defp apply_event(chat, %{"type" => "tool_execution_start"} = event) do
    running = Map.put(chat.running_tools, event["toolCallId"], event["toolName"])
    {%{chat | running_tools: running}, []}
  end

  defp apply_event(chat, %{"type" => "tool_execution_end", "toolCallId" => id}) do
    {%{chat | running_tools: Map.delete(chat.running_tools, id)}, []}
  end

  defp apply_event(chat, %{"type" => "run_start"}) do
    {%{chat | running?: true, failure: nil}, []}
  end

  defp apply_event(chat, %{"type" => "run_end"}) do
    {%{chat | running?: false, running_tools: %{}}, []}
  end

  defp apply_event(chat, %{"type" => "usage_changed", "usage" => usage}) do
    {%{chat | usage: usage}, []}
  end

  defp apply_event(chat, %{"type" => "session_failed"} = event) do
    {%{chat | running?: false, failure: Map.get(event, "error", "session failed")}, []}
  end

  defp apply_event(chat, _event) do
    {chat, []}
  end

  defp live_item(%{"message" => %{"content" => content}}, index) do
    %{id: @live_id, role: :assistant, blocks: blocks(content), index: index}
  end

  defp live_item(_generation, _index) do
    nil
  end

  defp settle_live(live, true) do
    {nil, Enum.map(List.wrap(live), &{:delete, &1})}
  end

  defp settle_live(live, false) do
    {live, []}
  end

  defp apply_change(%{"type" => type, "contentIndex" => index, "block" => block}, blocks)
       when type in ["text_start", "thinking_start", "toolcall_start", "block"] do
    put_block(blocks, index, block(block))
  end

  defp apply_change(%{"type" => "text_delta", "contentIndex" => index, "delta" => delta}, blocks) do
    append_text(blocks, index, :text, delta)
  end

  defp apply_change(
         %{"type" => "thinking_delta", "contentIndex" => index, "delta" => delta},
         blocks
       ) do
    append_text(blocks, index, :thinking, delta)
  end

  defp apply_change(_change, blocks) do
    blocks
  end

  defp append_text(blocks, index, type, delta) do
    current = Enum.at(blocks, index)

    updated =
      case current do
        %{type: ^type, text: text} -> %{current | text: text <> delta}
        _other -> %{type: type, text: delta}
      end

    put_block(blocks, index, updated)
  end

  defp put_block(blocks, index, block) do
    padding = List.duplicate(%{type: :text, text: ""}, max(index + 1 - length(blocks), 0))
    List.replace_at(blocks ++ padding, index, block)
  end

  defp index_items(items, start) do
    items
    |> Enum.with_index(start)
    |> Enum.map(fn {item, index} -> Map.put(item, :index, index) end)
  end

  defp entry_items(%{"model" => messages, "id" => id}) do
    messages
    |> Enum.with_index()
    |> Enum.flat_map(fn {message, index} -> message_item(message, "entry-#{id}-#{index}") end)
  end

  defp entry_items(_entry) do
    []
  end

  defp message_item(%{"role" => "user", "content" => content}, id) do
    [%{id: id, role: :user, blocks: blocks(content)}]
  end

  defp message_item(%{"role" => "assistant", "content" => content} = message, id) do
    [%{id: id, role: :assistant, blocks: blocks(content), error: message["errorMessage"]}]
  end

  defp message_item(%{"role" => "toolResult"} = message, id) do
    block = %{
      type: :tool_result,
      name: message["toolName"],
      text:
        message
        |> Map.get("content", [])
        |> blocks()
        |> Enum.map_join("\n", &Map.get(&1, :text, "")),
      error?: message["isError"] == true
    }

    [%{id: id, role: :tool_result, blocks: [block]}]
  end

  defp message_item(_message, _id) do
    []
  end

  defp blocks(content) when is_binary(content) do
    [%{type: :text, text: content}]
  end

  defp blocks(content) when is_list(content) do
    Enum.map(content, &block/1)
  end

  defp blocks(_content) do
    []
  end

  defp block(%{"type" => "text", "text" => text}) do
    %{type: :text, text: text}
  end

  defp block(%{"type" => "thinking", "thinking" => text}) do
    %{type: :thinking, text: text}
  end

  defp block(%{"type" => "toolCall"} = call) do
    %{type: :tool_call, name: call["name"], arguments: call["arguments"] || %{}}
  end

  defp block(%{"type" => type}) do
    %{type: :unknown, text: "[#{type}]"}
  end
end
