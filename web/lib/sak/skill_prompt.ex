defmodule Sak.SkillPrompt do
  @moduledoc """
  The message sent to the agent when a skill is run from the command palette:
  it names the skill, says where its instructions are, and lists the values
  the person filled in. Empty values are left out.
  """

  @spec build(map(), %{String.t() => String.t()}) :: String.t()
  def build(skill, values) do
    intro =
      ~s(Use the "#{skill["name"]}" skill: read its instructions at #{skill["path"]} first, then follow them.)

    case lines(skill, values) do
      [] -> intro
      lines -> intro <> "\n\nArguments:\n" <> Enum.join(lines, "\n")
    end
  end

  defp lines(skill, values) do
    skill
    |> Map.get("arguments", [])
    |> Enum.flat_map(fn argument ->
      value = values |> Map.get(argument["name"], "") |> String.trim()
      if value == "", do: [], else: ["- #{argument["name"]}: #{value}"]
    end)
  end
end
