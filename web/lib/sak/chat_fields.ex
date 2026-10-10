defmodule Sak.ChatFields do
  @moduledoc """
  The visible text fields of one chat item. Rendering and search both read
  from here, so what can be searched is exactly what is on screen.
  """

  @tool_output_char_limit 2_000
  @argument_char_limit 120
  @summary_keys ["command", "path", "file_path"]

  @type kind :: :content | :reasoning | :description | :tool_content | :error
  @type field :: %{index: non_neg_integer(), kind: kind(), text: String.t()}
  @type opts :: %{thinking_visible?: boolean(), tool_output_visible?: boolean()}

  @spec fields(map(), opts()) :: [field()]
  def fields(item, opts) do
    block_fields =
      item.blocks
      |> Enum.with_index()
      |> Enum.flat_map(fn {block, index} -> block_field(block, index, opts) end)

    block_fields ++ error_field(item, length(item.blocks))
  end

  defp block_field(%{type: :text, text: text}, index, _opts) do
    present(index, :content, text)
  end

  defp block_field(%{type: :thinking, text: text}, index, %{thinking_visible?: true}) do
    present(index, :reasoning, text)
  end

  defp block_field(%{type: :thinking}, _index, _opts), do: []

  defp block_field(%{type: :tool_call} = block, index, _opts) do
    present(index, :description, describe(block))
  end

  defp block_field(%{type: :tool_result, text: text}, index, %{tool_output_visible?: true}) do
    present(index, :tool_content, truncate(text))
  end

  defp block_field(%{type: :tool_result}, _index, _opts), do: []

  defp block_field(%{text: text}, index, _opts), do: present(index, :content, text)
  defp block_field(_block, _index, _opts), do: []

  defp error_field(%{error: error}, index) when is_binary(error) do
    present(index, :error, error)
  end

  defp error_field(_item, _index), do: []

  defp present(index, kind, text) do
    case String.trim(text) do
      "" -> []
      trimmed -> [%{index: index, kind: kind, text: trimmed}]
    end
  end

  defp describe(%{name: name, arguments: arguments}) do
    "#{name} #{summarize(arguments)}"
  end

  defp summarize(arguments) when is_map(arguments) do
    case Enum.find_value(@summary_keys, &Map.get(arguments, &1)) do
      value when is_binary(value) -> value
      _none -> arguments |> JSON.encode!() |> clip()
    end
  end

  defp summarize(arguments), do: arguments |> JSON.encode!() |> clip()

  defp clip(text) do
    if String.length(text) > @argument_char_limit do
      String.slice(text, 0, @argument_char_limit) <> "…"
    else
      text
    end
  end

  defp truncate(text) do
    case String.length(text) do
      length when length > @tool_output_char_limit ->
        visible = String.slice(text, 0, @tool_output_char_limit)
        "#{visible}\n… output truncated (#{length - @tool_output_char_limit} more characters)"

      _length ->
        text
    end
  end
end
