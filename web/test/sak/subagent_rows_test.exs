defmodule Sak.SubagentRowsTest do
  use ExUnit.Case, async: true

  alias Sak.SubagentRows

  @subagents [
    %{"id" => 5, "name" => "read docs", "persona" => "default", "live" => false},
    %{"id" => 7, "name" => nil, "persona" => "reader", "live" => true},
    %{"id" => 6, "name" => "summarise", "persona" => "default", "live" => true},
    %{"id" => 4, "name" => "", "persona" => nil, "live" => false}
  ]

  test "only running subagents are listed by default, newest first" do
    # Arrange
    subagents = @subagents

    # Act
    rows = SubagentRows.rows(subagents, false)

    # Assert
    assert Enum.map(rows, & &1.id) == [7, 6]
    assert Enum.all?(rows, & &1.live?)
  end

  test "finished subagents follow the running ones when asked for, and unnamed ones get an id label" do
    # Arrange
    subagents = @subagents

    # Act
    rows = SubagentRows.rows(subagents, true)

    # Assert
    assert Enum.map(rows, & &1.id) == [7, 6, 5, 4]
    assert Enum.map(rows, & &1.label) == ["subagent #7", "summarise", "read docs", "subagent #4"]
  end

  test "counts split running from finished" do
    # Arrange
    subagents = @subagents

    # Act
    counts = SubagentRows.counts(subagents)

    # Assert
    assert counts == {2, 2}
  end
end
