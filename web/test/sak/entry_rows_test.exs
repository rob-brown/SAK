defmodule Sak.EntryRowsTest do
  use ExUnit.Case, async: true

  alias Sak.EntryRows

  defp record(id, kind, messages), do: %{"id" => id, "kind" => kind, "model" => messages}

  test "every entry kind gets a row with its position, id, label and one-line text" do
    # Arrange
    records = [
      record(8, "pi.user", [%{"role" => "user", "content" => "Run it\nplease"}]),
      record(11, "pi.system", [
        %{
          "role" => "system",
          "content" => "",
          "toolsAdded" => [%{"name" => "bash"}, %{"name" => "read"}]
        }
      ]),
      record(12, "pi.assistant", [
        %{
          "role" => "assistant",
          "content" => [
            %{"type" => "thinking", "thinking" => "hmm"},
            %{"type" => "toolCall", "name" => "bash", "arguments" => %{"command" => "echo hi"}}
          ]
        }
      ]),
      record(14, "pi.tool-result", [
        %{
          "role" => "toolResult",
          "toolName" => "bash",
          "isError" => false,
          "content" => [%{"type" => "text", "text" => "hi\n"}]
        }
      ]),
      record(16, "pi.assistant", [
        %{"role" => "assistant", "content" => [%{"type" => "text", "text" => "done"}]}
      ])
    ]

    # Act
    rows = EntryRows.rows(records)

    # Assert
    assert Enum.map(rows, &{&1.number, &1.id, &1.label, &1.text}) == [
             {1, 8, "user", "Run it please"},
             {2, 11, "system", "tools added: bash, read"},
             {3, 12, "assistant", "→ bash echo hi"},
             {4, 14, "tool", "bash: hi"},
             {5, 16, "assistant", "done"}
           ]
  end

  test "an assistant reply with text and tool calls mentions the calls, and errors are marked" do
    # Arrange
    records = [
      record(1, "pi.assistant", [
        %{
          "role" => "assistant",
          "content" => [
            %{"type" => "text", "text" => "Checking"},
            %{"type" => "toolCall", "name" => "read", "arguments" => %{}},
            %{"type" => "toolCall", "name" => "read", "arguments" => %{}}
          ]
        }
      ]),
      record(2, "pi.tool-result", [
        %{
          "role" => "toolResult",
          "toolName" => "read",
          "isError" => true,
          "content" => [%{"type" => "text", "text" => "nope"}]
        }
      ])
    ]

    # Act
    [assistant, tool] = EntryRows.rows(records)

    # Assert
    assert assistant.text == "Checking (+2 tool calls)"
    assert tool.text == "error read: nope"
  end

  test "long text is truncated and unknown kinds keep their name" do
    # Arrange
    long = String.duplicate("x", 1_000)
    records = [record(1, "pi.reset", [%{"role" => "user", "content" => long}])]

    # Act
    [row] = EntryRows.rows(records)

    # Assert
    assert row.label == "reset"
    assert String.length(row.text) == 300
  end

  test "detail is the pretty-printed messages of the entry" do
    # Arrange
    record = record(1, "pi.user", [%{"role" => "user", "content" => "hi"}])

    # Act
    detail = EntryRows.detail(record)

    # Assert
    assert detail =~ "\"role\": \"user\""
    assert detail =~ "\n"
  end

  test "a judge note gets its own label, a one-line summary and its data as the detail" do
    # Arrange
    data = %{
      "purpose" => "persona pick",
      "outcome" => "chose a persona for 1 of 2 prompts",
      "model" => "winnow:e4b",
      "ms" => 180,
      "probability" => 0.95,
      "acted" => true
    }

    record = %{"kind" => "sak.judge", "id" => 9, "data" => data}

    # Act
    [row] = EntryRows.rows([record])

    # Assert
    assert row.label == "judge"

    assert row.text ==
             "persona pick: chose a persona for 1 of 2 prompts (95%) · winnow:e4b, 180 ms"

    assert EntryRows.detail(record) =~ "\"purpose\": \"persona pick\""
  end
end
