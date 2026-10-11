defmodule Sak.Usage do
  @moduledoc """
  Totals for one conversation, folded from its raw history entries: tokens,
  cost and time per model, and calls and time per tool. Subagents are separate
  conversations and are not included.
  """

  @type model :: %{
          turns: non_neg_integer(),
          input: non_neg_integer(),
          output: non_neg_integer(),
          cache_read: non_neg_integer(),
          cache_write: non_neg_integer(),
          total: non_neg_integer(),
          cost: float(),
          ms: non_neg_integer()
        }

  @type tool :: %{calls: non_neg_integer(), ms: non_neg_integer()}

  @type t :: %{
          models: %{String.t() => model()},
          tools: %{String.t() => tool()},
          model_ms: non_neg_integer(),
          tool_ms: non_neg_integer(),
          tokens: non_neg_integer(),
          cost: float()
        }

  @spec summarize([map()]) :: t()
  def summarize(records) do
    summary =
      records
      |> Enum.flat_map(&Map.get(&1, "model", []))
      |> Enum.reduce(%{models: %{}, tools: %{}}, &add/2)

    models = Map.values(summary.models)

    %{
      models: summary.models,
      tools: summary.tools,
      model_ms: models |> Enum.map(& &1.ms) |> Enum.sum(),
      tool_ms: summary.tools |> Map.values() |> Enum.map(& &1.ms) |> Enum.sum(),
      tokens: models |> Enum.map(& &1.total) |> Enum.sum(),
      cost: models |> Enum.map(& &1.cost) |> Enum.sum()
    }
  end

  @spec duration(number() | nil) :: String.t()
  def duration(nil), do: "–"
  def duration(ms) when ms < 1_000, do: "#{round(ms)} ms"
  def duration(ms) when ms < 60_000, do: "#{Float.round(ms / 1_000, 1)} s"

  def duration(ms) do
    seconds = round(ms / 1_000)
    "#{div(seconds, 60)}m #{rem(seconds, 60)}s"
  end

  @spec tokens(number() | nil) :: String.t()
  def tokens(nil), do: "–"

  def tokens(count) do
    count
    |> round()
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  @spec cost(number()) :: String.t()
  def cost(amount) when amount > 0, do: "$#{:erlang.float_to_binary(amount * 1.0, decimals: 4)}"
  def cost(_amount), do: "–"

  defp add(%{"role" => "assistant"} = message, summary) do
    usage = message["usage"] || %{}
    name = message["model"] || "unknown"

    update =
      fn model ->
        %{
          model
          | turns: model.turns + 1,
            input: model.input + number(usage["input"]),
            output: model.output + number(usage["output"]),
            cache_read: model.cache_read + number(usage["cacheRead"]),
            cache_write: model.cache_write + number(usage["cacheWrite"]),
            total: model.total + number(usage["totalTokens"]),
            cost: model.cost + (get_in(usage, ["cost", "total"]) || 0),
            ms: model.ms + number(message["durationMs"])
        }
      end

    %{summary | models: Map.update(summary.models, name, update.(empty_model()), update)}
  end

  defp add(%{"role" => "toolResult", "toolName" => name} = message, summary) do
    ms = number(message["durationMs"])
    tool = fn tool -> %{tool | calls: tool.calls + 1, ms: tool.ms + ms} end
    %{summary | tools: Map.update(summary.tools, name, tool.(%{calls: 0, ms: 0}), tool)}
  end

  defp add(_message, summary), do: summary

  defp empty_model do
    %{turns: 0, input: 0, output: 0, cache_read: 0, cache_write: 0, total: 0, cost: 0.0, ms: 0}
  end

  defp number(value) when is_number(value), do: value
  defp number(_value), do: 0
end
