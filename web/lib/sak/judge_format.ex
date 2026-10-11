defmodule Sak.JudgeFormat do
  @moduledoc """
  Readable markdown for the judge tool: the state and questions of a call, and
  the typed answers that come back.
  """

  alias Sak.Fence

  @spec call(term()) :: String.t() | nil
  def call(%{"questions" => questions} = arguments) when is_map(questions) do
    sections = [
      "judge",
      "**State**\n\n" <> state(Map.get(arguments, "state")),
      "**Questions**" | Enum.map(Enum.sort(questions), &question/1)
    ]

    Enum.join(sections, "\n\n")
  end

  def call(_arguments), do: nil

  @spec result(String.t()) :: String.t() | nil
  def result(text) when is_binary(text) do
    case Jason.decode(text) do
      {:ok, answers} when is_map(answers) and map_size(answers) > 0 ->
        answers |> Enum.sort() |> Enum.map_join("\n\n", &answer/1)

      _other ->
        nil
    end
  end

  def result(_text), do: nil

  defp state(state) when is_binary(state) do
    case Jason.decode(state) do
      {:ok, decoded} when is_map(decoded) or is_list(decoded) ->
        Fence.wrap(Jason.encode!(decoded, pretty: true), "json")

      _text ->
        Fence.wrap(String.trim(state), "text")
    end
  end

  defp state(_state), do: "_none_"

  defp question({id, %{} = question}) do
    header = "**`#{id}`** · #{question["type"]}"
    instructions = to_string(question["instructions"] || "")

    [header, instructions, criteria(question["criteria"])]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  defp question({id, _question}), do: "**`#{id}`**"

  defp criteria(%{} = options) when map_size(options) > 0 do
    options
    |> Enum.sort()
    |> Enum.map_join("\n", fn {name, meaning} -> "- `#{name}`: #{meaning}" end)
  end

  defp criteria([_ | _] = levels) do
    levels
    |> Enum.with_index()
    |> Enum.map_join("\n", fn {meaning, level} -> "- `#{level}`: #{meaning_text(meaning)}" end)
  end

  defp criteria(_criteria), do: ""

  defp meaning_text(%{"what" => what}), do: what
  defp meaning_text(meaning) when is_binary(meaning), do: meaning
  defp meaning_text(meaning), do: Jason.encode!(meaning)

  defp answer({id, %{"type" => "choice", "choice" => choice} = answer}) do
    probabilities = Map.get(answer, "probabilities", %{})
    header = "**`#{id}`** · choice → `#{choice}` (#{percent(probabilities[choice])})"
    Enum.join([header | ranked(probabilities, &"`#{&1}`")], "\n")
  end

  defp answer({id, %{"type" => "noul", "noul" => probability}}) when is_number(probability) do
    "**`#{id}`** · yes/no → #{percent(probability)} yes"
  end

  defp answer({id, %{"type" => "score", "score" => score} = answer}) when is_number(score) do
    probabilities = Map.get(answer, "probabilities", %{})
    legend = Map.get(answer, "legend", %{})
    top = probabilities |> Map.keys() |> Enum.map(&String.to_integer/1) |> Enum.max(fn -> 0 end)
    header = "**`#{id}`** · score → #{Float.round(score * 1.0, 2)} of #{top}"
    Enum.join([header | ranked(probabilities, &level(&1, legend), :level)], "\n")
  end

  defp answer({id, other}) do
    "**`#{id}`**\n\n" <> Fence.wrap(Jason.encode!(other, pretty: true), "json")
  end

  defp level(key, legend) do
    case legend[key] do
      nil -> "`#{key}`"
      meaning -> "`#{key}` #{meaning_text(meaning)}"
    end
  end

  defp ranked(probabilities, label, order \\ :probability)

  defp ranked(probabilities, label, :probability) do
    probabilities
    |> Enum.sort_by(fn {_key, probability} -> -probability end)
    |> Enum.map(fn {key, probability} -> "- #{label.(key)}: #{percent(probability)}" end)
  end

  defp ranked(probabilities, label, :level) do
    probabilities
    |> Enum.sort_by(fn {key, _probability} -> String.to_integer(key) end)
    |> Enum.map(fn {key, probability} -> "- #{label.(key)}: #{percent(probability)}" end)
  end

  defp percent(probability) when is_number(probability), do: "#{round(probability * 100)}%"
  defp percent(_probability), do: "?"
end
