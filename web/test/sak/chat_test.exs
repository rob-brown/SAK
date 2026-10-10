defmodule Sak.ChatTest do
  use ExUnit.Case, async: true

  alias Sak.Chat

  defp user_entry(id, text) do
    %{
      "kind" => "pi.user",
      "id" => id,
      "model" => [%{"role" => "user", "content" => text}]
    }
  end

  defp assistant_entry(id, content) do
    %{
      "kind" => "pi.assistant",
      "id" => id,
      "model" => [%{"role" => "assistant", "content" => content}]
    }
  end

  defp tool_result_entry(id, name, text, error?) do
    %{
      "kind" => "pi.tool-result",
      "id" => id,
      "model" => [
        %{
          "role" => "toolResult",
          "toolName" => name,
          "content" => [%{"type" => "text", "text" => text}],
          "isError" => error?
        }
      ]
    }
  end

  defp system_entry(id) do
    %{"kind" => "pi.system", "id" => id, "model" => [%{"role" => "system", "content" => ""}]}
  end

  describe "from_snapshot/1" do
    test "turns entries into items and hides system entries" do
      # Arrange
      snapshot = %{
        "entries" => [
          user_entry(7, "hi"),
          system_entry(10),
          assistant_entry(11, [
            %{"type" => "thinking", "thinking" => "hmm"},
            %{"type" => "text", "text" => "hello"},
            %{"type" => "toolCall", "name" => "read", "arguments" => %{"path" => "a"}}
          ]),
          tool_result_entry(13, "read", "contents", false)
        ]
      }

      # Act
      chat = Chat.from_snapshot(snapshot)

      # Assert
      assert [%{role: :user}, %{role: :assistant, blocks: blocks}, %{role: :tool_result}] =
               Chat.items(chat)

      assert [
               %{type: :thinking, text: "hmm"},
               %{type: :text, text: "hello"},
               %{type: :tool_call, name: "read", arguments: %{"path" => "a"}}
             ] = blocks
    end

    test "marks the chat running when the snapshot carries a run" do
      # Arrange
      snapshot = %{"entries" => [], "run" => %{"inputs" => [8]}}

      # Act
      chat = Chat.from_snapshot(snapshot)

      # Assert
      assert chat.running?
    end
  end

  describe "apply_events/2" do
    test "streams deltas into the live item, then swaps it for the final entry" do
      # Arrange
      chat = Chat.from_snapshot(%{"entries" => []})

      start = %{
        "type" => "message_start",
        "message" => %{"role" => "assistant", "content" => []}
      }

      updates = %{
        "type" => "message_update",
        "changes" => [
          %{"type" => "thinking_delta", "contentIndex" => 0, "delta" => "think"},
          %{"type" => "thinking_delta", "contentIndex" => 0, "delta" => "ing"},
          %{
            "type" => "text_start",
            "contentIndex" => 1,
            "block" => %{"type" => "text", "text" => "Do"}
          },
          %{"type" => "text_delta", "contentIndex" => 1, "delta" => "ne"}
        ]
      }

      finish = %{
        "type" => "message_end",
        "entry" => assistant_entry(11, [%{"type" => "text", "text" => "Done"}])
      }

      # Act
      {streaming, _ops} = Chat.apply_events(chat, [start, updates])
      {settled, ops} = Chat.apply_events(streaming, [finish])

      # Assert
      assert [%{type: :thinking, text: "thinking"}, %{type: :text, text: "Done"}] =
               streaming.live.blocks

      assert settled.live == nil
      assert [{:delete, %{id: "live"}}, {:insert, %{id: "entry-11-0"}}] = ops
    end

    test "a user message ending while the assistant streams keeps the live item" do
      # Arrange
      chat = Chat.from_snapshot(%{"entries" => []})
      start = %{"type" => "message_start", "message" => %{"role" => "assistant", "content" => []}}
      {streaming, _} = Chat.apply_events(chat, [start])

      # Act
      {after_steer, ops} =
        Chat.apply_events(streaming, [
          %{"type" => "message_end", "entry" => user_entry(20, "wait")}
        ])

      # Assert
      assert after_steer.live != nil
      assert [{:insert, %{role: :user}}] = ops
    end

    test "tracks running tools and run state" do
      # Arrange
      chat = Chat.from_snapshot(%{"entries" => []})

      # Act
      {started, _} =
        Chat.apply_events(chat, [
          %{"type" => "run_start"},
          %{"type" => "tool_execution_start", "toolCallId" => "t1", "toolName" => "bash"}
        ])

      {ended, _} =
        Chat.apply_events(started, [
          %{"type" => "tool_execution_end", "toolCallId" => "t1"},
          %{"type" => "run_end"}
        ])

      # Assert
      assert started.running?
      assert started.running_tools == %{"t1" => "bash"}
      refute ended.running?
      assert ended.running_tools == %{}
    end

    test "a snapshot event replaces the state and asks the view to reset" do
      # Arrange
      chat = Chat.from_snapshot(%{"entries" => [user_entry(1, "old")]})
      fresh = %{"type" => "snapshot", "entries" => [user_entry(2, "new")]}

      # Act
      {replaced, ops} = Chat.apply_events(chat, [fresh])

      # Assert
      assert [:reset] = ops
      assert [%{id: "entry-2-0"}] = replaced.entries
    end

    test "ignores unknown events and unknown deltas" do
      # Arrange
      chat = Chat.from_snapshot(%{"entries" => []})
      start = %{"type" => "message_start", "message" => %{"role" => "assistant", "content" => []}}

      mystery = %{
        "type" => "message_update",
        "changes" => [%{"type" => "toolcall_delta", "contentIndex" => 0}]
      }

      # Act
      {result, _ops} = Chat.apply_events(chat, [start, mystery, %{"type" => "never_heard_of_it"}])

      # Assert
      assert result.live.blocks == []
    end

    test "tool results carry the error flag" do
      # Arrange
      chat = Chat.from_snapshot(%{"entries" => []})
      event = %{"type" => "message_end", "entry" => tool_result_entry(13, "bash", "boom", true)}

      # Act
      {result, _ops} = Chat.apply_events(chat, [event])

      # Assert
      assert [%{role: :tool_result, blocks: [%{error?: true, text: "boom", name: "bash"}]}] =
               result.entries
    end
  end
end
