defmodule Sak.ChatSearch do
  @moduledoc """
  Finds every occurrence of a term across a conversation's visible fields
  and steps through them, newest first. A match is
  `{item_index, field_index, occurrence}`.
  """

  alias Sak.ChatFields

  @type match :: {non_neg_integer(), non_neg_integer(), non_neg_integer()}

  @spec matches([map()], String.t() | nil, ChatFields.opts()) :: [match()]
  def matches(_items, term, _opts) when term in [nil, ""], do: []

  def matches(items, term, opts) do
    downcased = String.downcase(term)

    items
    |> Enum.flat_map(&item_matches(&1, downcased, opts))
    |> Enum.reverse()
  end

  @spec jump([match()], integer() | nil, integer()) :: integer() | nil
  def jump([], _index, _delta), do: nil
  def jump(_matches, nil, _delta), do: 0

  def jump(matches, index, delta) do
    Integer.mod(index + delta, length(matches))
  end

  defp item_matches(item, term, opts) do
    item
    |> ChatFields.fields(opts)
    |> Enum.flat_map(fn field ->
      field.text
      |> String.downcase()
      |> count(term)
      |> occurrences()
      |> Enum.map(&{item.index, field.index, &1})
    end)
  end

  defp count(text, term) do
    count(text, term, 0, 0)
  end

  defp count(text, term, offset, total) do
    remaining = binary_part(text, offset, byte_size(text) - offset)

    case :binary.match(remaining, term) do
      :nomatch -> total
      {start, length} -> count(text, term, offset + start + length, total + 1)
    end
  end

  defp occurrences(0), do: []

  defp occurrences(count) do
    Enum.to_list(0..(count - 1))
  end
end
