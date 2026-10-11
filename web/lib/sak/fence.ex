defmodule Sak.Fence do
  @moduledoc """
  Markdown code fences that stay valid when the text inside contains backticks.
  """

  @spec wrap(String.t(), String.t()) :: String.t()
  def wrap(text, language) do
    fence = String.duplicate("`", max(3, longest_backtick_run(text) + 1))
    fence <> language <> "\n" <> text <> "\n" <> fence
  end

  defp longest_backtick_run(text) do
    ~r/`+/
    |> Regex.scan(text)
    |> Enum.map(fn [run] -> String.length(run) end)
    |> Enum.max(fn -> 0 end)
  end
end
