defmodule Sak.UsageTest do
  use ExUnit.Case, async: true

  alias Sak.Usage

  defp assistant(model, input, output, ms, cost \\ 0.0) do
    %{
      "model" => [
        %{
          "role" => "assistant",
          "model" => model,
          "durationMs" => ms,
          "usage" => %{
            "input" => input,
            "output" => output,
            "cacheRead" => 10,
            "cacheWrite" => 0,
            "totalTokens" => input + output,
            "cost" => %{"total" => cost}
          }
        }
      ]
    }
  end

  defp tool(name, ms) do
    %{"model" => [%{"role" => "toolResult", "toolName" => name, "durationMs" => ms}]}
  end

  test "tokens, cost and time are summed per model and per tool, ignoring other entries" do
    # Arrange
    records = [
      %{"kind" => "sak.judge", "data" => %{}},
      assistant("a", 100, 20, 1_500, 0.01),
      tool("bash", 200),
      assistant("a", 300, 40, 2_500, 0.02),
      assistant("b", 50, 5, 500),
      tool("bash", 300),
      tool("read", 10),
      %{"model" => [%{"role" => "user", "content" => "hi"}]}
    ]

    # Act
    summary = Usage.summarize(records)

    # Assert
    assert %{turns: 2, input: 400, output: 60, cache_read: 20, total: 460, ms: 4_000} =
             summary.models["a"]

    assert_in_delta summary.models["a"].cost, 0.03, 1.0e-9
    assert summary.models["b"].turns == 1
    assert summary.tools == %{"bash" => %{calls: 2, ms: 500}, "read" => %{calls: 1, ms: 10}}
    assert {summary.model_ms, summary.tool_ms, summary.tokens} == {4_500, 510, 515}
  end

  test "missing numbers count as zero and an empty history is an empty summary" do
    # Arrange
    sparse = [
      %{"model" => [%{"role" => "assistant"}, %{"role" => "toolResult", "toolName" => "bash"}]}
    ]

    # Act
    summary = Usage.summarize(sparse)
    empty = Usage.summarize([])

    # Assert
    assert summary.models["unknown"].turns == 1
    assert summary.tools["bash"] == %{calls: 1, ms: 0}
    assert {empty.tokens, empty.model_ms, empty.cost} == {0, 0, 0}
  end

  test "durations, token counts and costs are shown the way people read them" do
    # Arrange
    # Act
    durations = Enum.map([nil, 120, 1_840, 72_000], &Usage.duration/1)

    # Assert
    assert durations == ["–", "120 ms", "1.8 s", "1m 12s"]
    assert Usage.tokens(1_234_567) == "1,234,567"
    assert Usage.tokens(12) == "12"
    assert Usage.cost(0.0123) == "$0.0123"
    assert Usage.cost(0) == "–"
  end
end
