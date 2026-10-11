defmodule Sak.AgentFormat do
  @moduledoc """
  Readable markdown for the agent tool: the prompts handed to subagents, and
  the answers that come back in the same order. Long lists and long texts are
  cut for display and say so.
  """

  @max_items 3
  @prompt_chars 400
  @answer_chars 2_000

  @spec call(term()) :: String.t() | nil
  def call(%{"prompts" => [_ | _] = prompts} = arguments) do
    count = length(prompts)
    noun = if count == 1, do: "subagent", else: "subagents"
    header = ["agent", "#{count} #{noun}", persona(Map.get(arguments, "persona"))]

    Enum.join(
      [
        header |> Enum.reject(&is_nil/1) |> Enum.join(" · ")
        | numbered_list(prompts, "prompt", @prompt_chars)
      ],
      "\n\n"
    )
  end

  def call(_arguments), do: nil

  @spec result(String.t()) :: String.t() | nil
  def result(text) when is_binary(text) do
    case Jason.decode(text) do
      {:ok, [_ | _] = answers} ->
        answers |> numbered_list("answer", @answer_chars) |> Enum.join("\n\n")

      _other ->
        nil
    end
  end

  def result(_text), do: nil

  defp persona(persona) when is_binary(persona) and persona != "", do: "persona: #{persona}"
  defp persona(_persona), do: nil

  defp numbered_list(texts, noun, limit) do
    shown =
      texts
      |> Enum.take(@max_items)
      |> Enum.with_index(1)
      |> Enum.map(fn {text, number} -> numbered(number, text, limit) end)

    hidden = length(texts) - @max_items

    if hidden > 0 do
      shown ++ ["_… #{hidden} more #{noun}#{if hidden == 1, do: "", else: "s"} not shown_"]
    else
      shown
    end
  end

  defp numbered(number, text, limit) do
    body = text |> to_string() |> String.trim() |> clip(limit) |> quote_lines()
    "**#{number}.**\n\n#{body}"
  end

  defp clip(text, limit) do
    case String.length(text) - limit do
      extra when extra > 0 -> String.slice(text, 0, limit) <> "\n\n… #{extra} more characters"
      _fits -> text
    end
  end

  defp quote_lines(text) do
    text
    |> String.split(~r/\r?\n/)
    |> Enum.map_join("\n", fn
      "" -> ">"
      line -> "> " <> line
    end)
  end
end
