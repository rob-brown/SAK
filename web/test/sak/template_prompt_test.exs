defmodule Sak.TemplatePromptTest do
  use ExUnit.Case, async: true

  alias Sak.TemplatePrompt

  defp answer(fields, answers) do
    Enum.map(fields, &%{&1 | value: Map.get(answers, &1.name, "")})
  end

  test "asks the five questions in order" do
    # Arrange
    fields = TemplatePrompt.fields()

    # Act
    names = Enum.map(fields, & &1.name)

    # Assert
    assert names == ["task", "context", "authority", "evidence", "escalation"]
  end

  test "wraps each answer in a tag named after its question" do
    # Arrange
    fields =
      answer(TemplatePrompt.fields(), %{"task" => "Build feature X.", "evidence" => "Tests pass."})

    # Act
    prompt = TemplatePrompt.build(fields)

    # Assert
    assert prompt == "<task>\nBuild feature X.\n</task>\n\n<evidence>\nTests pass.\n</evidence>"
  end

  test "omits tags whose answer is empty or only whitespace" do
    # Arrange
    fields = answer(TemplatePrompt.fields(), %{"task" => "Do it", "context" => "  \n "})

    # Act
    prompt = TemplatePrompt.build(fields)

    # Assert
    assert prompt == "<task>\nDo it\n</task>"
  end

  test "builds nothing when every answer is empty" do
    assert TemplatePrompt.build(TemplatePrompt.fields()) == ""
  end
end
