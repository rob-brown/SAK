defmodule Sak.Command do
  alias Sak.FuzzyMatch

  @enforce_keys [:name, :description]
  defstruct [:name, :description, aliases: [], inputs: [], kind: :builtin, skill: nil]

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          aliases: [String.t()],
          inputs: [map()],
          kind: :builtin | :skill,
          skill: map() | nil
        }

  @min_filter_length 2

  @spec list() :: [t()]
  def list do
    [
      %__MODULE__{
        name: "model",
        description: "List the models the endpoint offers and show the one in use"
      },
      %__MODULE__{
        name: "permissions",
        aliases: ["mode"],
        description: "Choose when this session asks before running tools"
      },
      %__MODULE__{
        name: "usage",
        description: "Show tokens, time and cost for this session"
      },
      %__MODULE__{
        name: "clear",
        aliases: ["new"],
        description: "Reset the conversation to a fresh session"
      }
    ]
  end

  @description_limit 90

  @spec from_skills([map()]) :: [t()]
  def from_skills(skills) do
    Enum.map(skills, fn skill ->
      %__MODULE__{
        name: "skill:" <> skill["name"],
        description: "Skill: " <> clip(skill["description"]),
        inputs: Map.get(skill, "arguments", []),
        kind: :skill,
        skill: skill
      }
    end)
  end

  defp clip(text) when byte_size(text) > @description_limit do
    String.slice(text, 0, @description_limit) <> "…"
  end

  defp clip(text), do: text

  @spec filter([t()], String.t()) :: [t()]
  def filter(commands \\ list(), query)

  def filter(commands, query) when byte_size(query) < @min_filter_length, do: commands

  def filter(commands, query) do
    commands
    |> Enum.map(&{&1, best_score(&1, query)})
    |> Enum.reject(fn {_command, score} -> is_nil(score) end)
    |> Enum.sort_by(fn {command, score} -> {-score, command.name} end)
    |> Enum.map(fn {command, _score} -> command end)
  end

  defp best_score(command, query) do
    [command.name | command.aliases]
    |> Enum.concat([command.description])
    |> Enum.map(&FuzzyMatch.score(&1, query))
    |> Enum.reject(&is_nil/1)
    |> Enum.max(fn -> nil end)
  end
end
