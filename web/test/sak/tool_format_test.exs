defmodule Sak.ToolFormatTest do
  use ExUnit.Case, async: true

  alias Sak.AgentFormat
  alias Sak.ChatFields
  alias Sak.JudgeFormat

  @shown %{thinking_visible?: true, tool_output_visible?: true}

  defp item(block), do: %{index: 0, role: :assistant, blocks: [block]}

  test "a judge call shows the state as formatted JSON and each question with its criteria" do
    # Arrange
    arguments = %{
      "state" => ~s({"command":"rm -rf src","facts":["src is tracked"]}),
      "questions" => %{
        "risk" => %{
          "type" => "score",
          "instructions" => "How risky is `command`?",
          "criteria" => ["harmless", "destructive"]
        },
        "kind" => %{
          "type" => "choice",
          "instructions" => "Which kind?",
          "criteria" => %{"read" => "only reads", "write" => "changes files"}
        }
      }
    }

    # Act
    text = JudgeFormat.call(arguments)

    # Assert
    assert String.starts_with?(
             text,
             "judge\n\n**State**\n\n```json\n{\n  \"command\": \"rm -rf src\""
           )

    assert text =~
             "**`kind`** · choice\n\nWhich kind?\n\n- `read`: only reads\n- `write`: changes files"

    assert text =~
             "**`risk`** · score\n\nHow risky is `command`?\n\n- `0`: harmless\n- `1`: destructive"

    assert String.contains?(text, "**Questions**")
  end

  test "state that is not JSON is shown as plain text and a fence grows around backticks" do
    # Arrange
    arguments = %{
      "state" => "some ``` text",
      "questions" => %{"q" => %{"type" => "noul", "instructions" => "Is it?"}}
    }

    # Act
    text = JudgeFormat.call(arguments)

    # Assert
    assert text =~ "````text\nsome ``` text\n````"
    assert text =~ "**`q`** · noul\n\nIs it?"
  end

  test "judge answers are shown per question with their probabilities, whatever the type" do
    # Arrange
    answers = %{
      "kind" => %{
        "type" => "choice",
        "choice" => "write",
        "confidence" => 0.5,
        "probabilities" => %{"read" => 0.16, "write" => 0.84}
      },
      "danger" => %{"type" => "noul", "noul" => 0.97},
      "risk" => %{
        "type" => "score",
        "score" => 2.91,
        "probabilities" => %{"0" => 0.0, "1" => 0.09, "2" => 0.0, "3" => 0.91},
        "legend" => %{"0" => "harmless", "3" => "destructive"}
      },
      "odd" => %{"type" => "mystery", "value" => 1}
    }

    # Act
    text = answers |> Jason.encode!() |> JudgeFormat.result()

    # Assert
    assert text =~ "**`kind`** · choice → `write` (84%)\n- `write`: 84%\n- `read`: 16%"
    assert text =~ "**`danger`** · yes/no → 97% yes"

    assert text =~
             "**`risk`** · score → 2.91 of 3\n- `0` harmless: 0%\n- `1`: 9%\n- `2`: 0%\n- `3` destructive: 91%"

    assert text =~ "**`odd`**\n\n```json\n{\n  \"type\": \"mystery\""
  end

  test "text that is not judge answers is left for the generic output" do
    # Arrange
    messages = ["question \"x\": a choice needs criteria", "[1,2]", ""]

    # Act
    results = Enum.map(messages, &JudgeFormat.result/1)

    # Assert
    assert results == [nil, nil, nil]
  end

  test "an agent call numbers its prompts, keeps their lines and names the persona" do
    # Arrange
    arguments = %{
      "prompts" => ["Review the diff.\n\nBe brief.", "Check tests."],
      "persona" => "reviewer"
    }

    # Act
    text = AgentFormat.call(arguments)

    # Assert
    assert text ==
             "agent · 2 subagents · persona: reviewer\n\n**1.**\n\n> Review the diff.\n>\n> Be brief.\n\n**2.**\n\n> Check tests."
  end

  test "a single prompt without a persona is a one-subagent header" do
    # Arrange
    arguments = %{"prompts" => ["Look at it."]}

    # Act
    text = AgentFormat.call(arguments)

    # Assert
    assert text == "agent · 1 subagent\n\n**1.**\n\n> Look at it."
    assert AgentFormat.call(%{"prompts" => []}) == nil
  end

  test "agent answers come back numbered in order, and failures stay visible" do
    # Arrange
    answers = Jason.encode!(["All good.\n- one", "Error: aborted"])

    # Act
    text = AgentFormat.result(answers)

    # Assert
    assert text == "**1.**\n\n> All good.\n> - one\n\n**2.**\n\n> Error: aborted"
    assert AgentFormat.result("unknown persona ghost") == nil
  end

  test "judge and agent calls are code-style fields, and results are formatted only when output is shown" do
    # Arrange
    judge_call = %{
      type: :tool_call,
      name: "judge",
      arguments: %{
        "state" => "x",
        "questions" => %{"q" => %{"type" => "noul", "instructions" => "Is it?"}}
      }
    }

    agent_call = %{type: :tool_call, name: "agent", arguments: %{"prompts" => ["go"]}}

    judge_result = %{
      type: :tool_result,
      name: "judge",
      text: ~s({"q":{"type":"noul","noul":0.5}})
    }

    failure = %{type: :tool_result, name: "agent", text: "unknown persona ghost"}

    # Act
    [judge_field] = ChatFields.fields(item(judge_call), @shown)
    [agent_field] = ChatFields.fields(item(agent_call), @shown)
    [result_field] = ChatFields.fields(item(judge_result), @shown)
    [failure_field] = ChatFields.fields(item(failure), @shown)
    hidden = ChatFields.fields(item(judge_result), %{@shown | tool_output_visible?: false})

    # Assert
    assert {judge_field.kind, agent_field.kind} == {:code_call, :code_call}
    assert result_field.text == "**`q`** · yes/no → 50% yes"
    assert failure_field.text == "unknown persona ghost"
    assert hidden == []
  end

  test "other tool calls and malformed judge or agent arguments keep the one-line description" do
    # Arrange
    bash = %{type: :tool_call, name: "bash", arguments: %{"command" => "ls"}}
    broken_agent = %{type: :tool_call, name: "agent", arguments: %{"prompts" => "not a list"}}

    # Act
    [bash_field] = ChatFields.fields(item(bash), @shown)
    [agent_field] = ChatFields.fields(item(broken_agent), @shown)

    # Assert
    assert {bash_field.kind, bash_field.text} == {:description, "bash ls"}
    assert agent_field.kind == :description
  end
end
