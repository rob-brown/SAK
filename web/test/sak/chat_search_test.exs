defmodule Sak.ChatSearchTest do
  use ExUnit.Case, async: true

  alias Sak.ChatSearch

  @opts %{thinking_visible?: true, tool_output_visible?: false}

  defp item(index, blocks), do: %{index: index, role: :assistant, blocks: blocks}
  defp text(value), do: %{type: :text, text: value}

  test "matches every occurrence, newest item first" do
    # Arrange
    items = [item(0, [text("aa aa")]), item(1, [text("aa")])]

    # Act
    matches = ChatSearch.matches(items, "AA", @opts)

    # Assert
    assert matches == [{1, 0, 0}, {0, 0, 1}, {0, 0, 0}]
  end

  test "hidden thinking and hidden tool output are not searchable" do
    # Arrange
    items = [
      item(0, [
        %{type: :thinking, text: "needle"},
        %{type: :tool_result, name: "bash", text: "needle"}
      ])
    ]

    hidden = %{thinking_visible?: false, tool_output_visible?: false}
    shown = %{thinking_visible?: true, tool_output_visible?: true}

    # Act
    results =
      {ChatSearch.matches(items, "needle", hidden), ChatSearch.matches(items, "needle", shown)}

    # Assert
    assert {[], [{0, 1, 0}, {0, 0, 0}]} == results
  end

  test "an empty term has no matches" do
    # Arrange
    items = [item(0, [text("anything")])]

    # Act
    matches = ChatSearch.matches(items, "", @opts)

    # Assert
    assert matches == []
  end

  test "jump starts at the newest match and wraps around" do
    # Arrange
    matches = [:a, :b, :c]

    # Act
    results = [
      ChatSearch.jump(matches, nil, 1),
      ChatSearch.jump(matches, 2, 1),
      ChatSearch.jump(matches, 0, -1),
      ChatSearch.jump([], nil, 1)
    ]

    # Assert
    assert results == [0, 0, 2, nil]
  end
end
