defmodule Sak.SubagentRows do
  @moduledoc """
  Rows of the Subagents tab: live children first, finished ones only when
  asked for, newest first within each group.
  """

  @type row :: %{id: integer(), label: String.t(), persona: String.t() | nil, live?: boolean()}

  @spec rows([map()], boolean()) :: [row()]
  def rows(subagents, show_finished?) do
    subagents
    |> Enum.filter(&(live?(&1) or show_finished?))
    |> Enum.sort_by(&{if(live?(&1), do: 0, else: 1), -&1["id"]})
    |> Enum.map(&row/1)
  end

  @spec counts([map()]) :: {non_neg_integer(), non_neg_integer()}
  def counts(subagents) do
    live = Enum.count(subagents, &live?/1)
    {live, length(subagents) - live}
  end

  defp row(subagent) do
    %{
      id: subagent["id"],
      label: label(subagent),
      persona: subagent["persona"],
      live?: live?(subagent)
    }
  end

  defp label(%{"name" => name}) when is_binary(name) and name != "", do: name
  defp label(%{"id" => id}), do: "subagent ##{id}"

  defp live?(subagent), do: subagent["live"] == true
end
