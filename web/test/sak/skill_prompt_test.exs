defmodule Sak.SkillPromptTest do
  use ExUnit.Case, async: true

  alias Sak.SkillPrompt

  @skill %{
    "name" => "report",
    "path" => "/proj/.agents/skills/report/SKILL.md",
    "arguments" => [
      %{"name" => "topic", "required" => true},
      %{"name" => "length", "default" => "short"},
      %{"name" => "tone"}
    ]
  }

  test "the message names the skill and its file, then lists the filled-in arguments in order" do
    # Arrange
    values = %{"topic" => "  Q3 results ", "length" => "short"}

    # Act
    message = SkillPrompt.build(@skill, values)

    # Assert
    assert message =~ ~s(Use the "report" skill)
    assert message =~ "/proj/.agents/skills/report/SKILL.md"
    assert message =~ "Arguments:\n- topic: Q3 results\n- length: short"
    refute message =~ "tone"
  end

  test "a skill with no arguments, or with every value left blank, is just the instruction" do
    # Arrange
    plain = Map.delete(@skill, "arguments")

    # Act
    without = SkillPrompt.build(plain, %{})
    blank = SkillPrompt.build(@skill, %{"topic" => " ", "length" => ""})

    # Assert
    assert without == blank
    refute without =~ "Arguments"
  end
end
