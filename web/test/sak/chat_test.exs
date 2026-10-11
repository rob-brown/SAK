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

    test "shows a context item listing the loaded instruction files" do
      # Arrange
      text =
        ~s(<project_instructions>\n<instructions path="/home/me/.config/sak/AGENTS.md">\na\n</instructions>\n<instructions path="/repo/CLAUDE.md">\nb\n</instructions>\n</project_instructions>)

      entry = %{
        "kind" => "pi.system",
        "id" => 3,
        "model" => [%{"role" => "system", "sections" => %{"project_instructions" => text}}]
      }

      # Act
      chat = Chat.from_snapshot(%{"entries" => [entry, user_entry(4, "hi")]})

      # Assert
      assert [%{role: :system, blocks: [%{type: :context, text: summary}]}, %{role: :user}] =
               Chat.items(chat)

      assert summary =~ "- `/home/me/.config/sak/AGENTS.md`"
      assert summary =~ "- `/repo/CLAUDE.md`"
    end

    test "lists loaded skills in the same context item and ignores sections that are removed" do
      # Arrange
      skills =
        ~s(<skills>\npreface\n<skill name="pdf" location="/s/pdf/SKILL.md">Fill forms</skill>\n<skill name="sql" location="/s/sql/SKILL.md">Query</skill>\n</skills>)

      entry = %{
        "kind" => "pi.system",
        "id" => 3,
        "model" => [
          %{
            "role" => "system",
            "sections" => %{"skills" => skills, "project_instructions" => nil}
          }
        ]
      }

      # Act
      chat = Chat.from_snapshot(%{"entries" => [entry]})

      # Assert
      assert [%{role: :system, blocks: [%{type: :context, text: summary}]}] = Chat.items(chat)
      assert summary == "Loaded skills:\n\n- `pdf`\n- `sql`"
    end

    test "a skill suggestion in front of a user message becomes its own muted item" do
      # Arrange
      text =
        ~s(<skill-suggestion name="pdf" confidence="0.93">A decision model judged that the "pdf" skill fits.</skill-suggestion>\n\nfill in this form)

      # Act
      chat = Chat.from_snapshot(%{"entries" => [user_entry(5, text), user_entry(6, "plain")]})

      # Assert
      assert [
               %{role: :system, blocks: [%{type: :context, text: hint}]},
               %{role: :user, blocks: [%{text: "fill in this form"}]},
               %{role: :user, blocks: [%{text: "plain"}]}
             ] = Chat.items(chat)

      assert hint == "Suggested skill: `pdf` (93% sure)"
    end

    test "a judge note shows in the chat only when it changed something other than a skill suggestion" do
      # Arrange
      note = fn id, purpose, acted ->
        %{
          "kind" => "sak.judge",
          "id" => id,
          "data" => %{
            "purpose" => purpose,
            "outcome" => "chose a persona for 1 of 2 prompts",
            "acted" => acted,
            "probability" => 0.95
          }
        }
      end

      entries = [
        note.(1, "persona pick", true),
        note.(2, "persona pick", false),
        note.(3, "skill suggestion", true),
        note.(4, "permission", true)
      ]

      # Act
      chat = Chat.from_snapshot(%{"entries" => entries})

      # Assert
      assert [
               %{role: :system, blocks: [%{type: :context, text: first}]},
               %{role: :system, blocks: [%{type: :context, text: second}]}
             ] = Chat.items(chat)

      assert first == "Judge, persona pick: chose a persona for 1 of 2 prompts (95% sure)"
      assert second =~ "Judge, permission:"
    end

    test "assistant replies and tool results carry the time and token stats from the history" do
      # Arrange
      assistant =
        assistant_entry(5, [%{"type" => "text", "text" => "hi"}])
        |> update_in(["model", Access.at(0)], fn message ->
          Map.merge(message, %{
            "durationMs" => 900,
            "usage" => %{"input" => 10, "output" => 3, "cacheRead" => 7}
          })
        end)

      result =
        tool_result_entry(6, "bash", "out", false)
        |> update_in(["model", Access.at(0)], &Map.put(&1, "durationMs", 45))

      # Act
      chat = Chat.from_snapshot(%{"entries" => [assistant, result]})

      # Assert
      assert [
               %{stats: %{kind: :model, ms: 900, input: 10, output: 3, cache_read: 7}},
               %{stats: %{kind: :tool, name: "bash", ms: 45}}
             ] = Chat.items(chat)
    end

    test "restores the in-flight assistant message from the generation field" do
      # Arrange
      snapshot = %{
        "entries" => [user_entry(8, "count")],
        "run" => %{"inputs" => [9]},
        "generation" => %{
          "attempt" => 1,
          "message" => %{
            "role" => "assistant",
            "content" => [%{"type" => "text", "text" => "1\n2\n"}]
          }
        }
      }

      # Act
      chat = Chat.from_snapshot(snapshot)

      {continued, _ops} =
        Chat.apply_events(chat, [
          %{
            "type" => "message_update",
            "changes" => [%{"type" => "text_delta", "contentIndex" => 0, "delta" => "3\n"}]
          }
        ])

      # Assert
      assert [%{role: :user}, %{id: "live", blocks: [%{text: "1\n2\n"}]}] = Chat.items(chat)
      assert [%{text: "1\n2\n3\n"}] = continued.live.blocks
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

    test "total_tokens sums usage across models" do
      # Arrange
      chat = Chat.from_snapshot(%{"entries" => []})

      usage = %{
        "models" => %{
          "a/x" => %{"totalTokens" => 100},
          "b/y" => %{"totalTokens" => 23}
        }
      }

      # Act
      {updated, _ops} = Chat.apply_events(chat, [%{"type" => "usage_changed", "usage" => usage}])

      # Assert
      assert Chat.total_tokens(updated) == 123
      assert Chat.total_tokens(chat) == 0
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
