defmodule Sak.AgentFormat do
  @moduledoc """
  Readable markdown for the agent tool: the prompts handed to subagents, and
  the answers that come back in the same order.
  """

  @spec call(term()) :: String.t() | nil
  def call(%{"prompts" => [_ | _] = prompts} = arguments) do
    count = length(prompts)
    noun = if count == 1, do: "subagent", else: "subagents"
    header = ["agent", "#{count} #{noun}", persona(Map.get(arguments, "persona"))]

    items =
      prompts
      |> Enum.with_index(1)
      |> Enum.map(fn {prompt, number} -> numbered(number, prompt) end)

    Enum.join([header |> Enum.reject(&is_nil/1) |> Enum.join(" · ") | items], "\n\n")
  end

  def call(_arguments), do: nil

  @spec result(String.t()) :: String.t() | nil
  def result(text) when is_binary(text) do
    case Jason.decode(text) do
      {:ok, [_ | _] = answers} ->
        answers
        |> Enum.with_index(1)
        |> Enum.map_join("\n\n", fn {answer, number} -> numbered(number, answer) end)

      _other ->
        nil
    end
  end

  def result(_text), do: nil

  defp persona(persona) when is_binary(persona) and persona != "", do: "persona: #{persona}"
  defp persona(_persona), do: nil

  defp numbered(number, text) do
    body = text |> to_string() |> String.trim() |> quote_lines()
    "**#{number}.**\n\n#{body}"
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
