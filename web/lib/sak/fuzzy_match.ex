defmodule Sak.FuzzyMatch do
  @contiguous_bonus 2
  @boundary_bonus 2

  @spec score(String.t(), String.t()) :: integer() | nil
  def score(_candidate, "") do
    0
  end

  def score(candidate, query) do
    chars = candidate |> String.downcase() |> String.graphemes()
    needles = query |> String.downcase() |> String.graphemes()

    chars
    |> Enum.with_index()
    |> Enum.reduce({0, nil, nil, needles}, &match_step(&1, &2, chars))
    |> finish()
  end

  @spec filter([String.t()], String.t()) :: [String.t()]
  def filter(paths, "") do
    paths
  end

  def filter(paths, query) do
    paths
    |> Enum.map(&{&1, score(&1, query)})
    |> Enum.reject(fn {_path, score} -> is_nil(score) end)
    |> Enum.sort_by(fn {path, score} -> {-score, String.length(path), path} end)
    |> Enum.map(fn {path, _score} -> path end)
  end

  defp match_step(_indexed_char, {_total, _first, _prev, []} = acc, _chars) do
    acc
  end

  defp match_step({char, index}, {total, first, prev, [needle | rest]}, chars)
       when char == needle do
    contiguous_bonus = boolean_bonus(prev == index - 1, @contiguous_bonus)

    boundary_bonus =
      boolean_bonus(index == 0 or Enum.at(chars, index - 1) == "/", @boundary_bonus)

    {total + 1 + contiguous_bonus + boundary_bonus, first || index, index, rest}
  end

  defp match_step(_indexed_char, acc, _chars) do
    acc
  end

  defp boolean_bonus(true, bonus), do: bonus
  defp boolean_bonus(false, _bonus), do: 0

  defp finish({_total, _first, _prev, [_ | _]}), do: nil
  defp finish({total, first, _prev, []}), do: total - (first || 0)
end
