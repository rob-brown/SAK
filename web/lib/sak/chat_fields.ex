defmodule Sak.ChatFields do
  @moduledoc """
  The visible text fields of one chat item. Rendering and search both read
  from here, so what can be searched is exactly what is on screen.
  """

  @tool_output_char_limit 2_000
  @argument_char_limit 120
  @summary_keys ["command", "path", "file_path", "code"]

  @type kind ::
          :content
          | :context
          | :reasoning
          | :description
          | :code_call
          | :tool_content
          | :error
          | :stats
  @type field :: %{index: non_neg_integer(), kind: kind(), text: String.t()}
  @type opts :: %{
          required(:thinking_visible?) => boolean(),
          required(:tool_output_visible?) => boolean(),
          optional(:stats_visible?) => boolean()
        }

  @spec fields(map(), opts()) :: [field()]
  def fields(item, opts) do
    block_fields =
      item.blocks
      |> Enum.with_index()
      |> Enum.flat_map(fn {block, index} -> block_field(block, index, opts) end)

    block_fields ++
      error_field(item, length(item.blocks)) ++ stats_field(item, opts, length(item.blocks) + 1)
  end

  defp block_field(%{type: :text, text: text}, index, _opts) do
    present(index, :content, text)
  end

  defp block_field(%{type: :thinking, text: text}, index, %{thinking_visible?: true}) do
    present(index, :reasoning, text)
  end

  defp block_field(%{type: :thinking}, _index, _opts), do: []

  defp block_field(
         %{type: :tool_call, name: "codemode", arguments: %{"code" => code}},
         index,
         _opts
       )
       when is_binary(code) do
    present(index, :code_call, "codemode\n\n" <> fenced(code))
  end

  defp block_field(%{type: :tool_call} = block, index, _opts) do
    present(index, :description, describe(block))
  end

  defp block_field(%{type: :tool_result, text: text}, index, %{tool_output_visible?: true}) do
    present(index, :tool_content, truncate(text))
  end

  defp block_field(%{type: :tool_result}, _index, _opts), do: []

  defp block_field(%{type: :context, text: text}, index, _opts) do
    present(index, :context, text)
  end

  defp block_field(%{text: text}, index, _opts) do
    present(index, :content, text)
  end

  defp block_field(_block, _index, _opts), do: []

  defp error_field(%{error: error}, index) when is_binary(error) do
    present(index, :error, error)
  end

  defp error_field(_item, _index), do: []

  defp stats_field(%{stats: stats}, %{stats_visible?: true}, index) when is_map(stats) do
    case stats_text(stats) do
      "" -> []
      text -> [%{index: index, kind: :stats, text: text}]
    end
  end

  defp stats_field(_item, _opts, _index), do: []

  defp stats_text(%{kind: :tool, name: name, ms: ms}) when is_number(ms) do
    "#{name} · #{Sak.Usage.duration(ms)}"
  end

  defp stats_text(%{kind: :model} = stats) do
    [
      stats.ms && Sak.Usage.duration(stats.ms),
      stats.input && "#{Sak.Usage.tokens(stats.input)} in",
      stats.output && "#{Sak.Usage.tokens(stats.output)} out",
      positive(stats.cache_read) && "#{Sak.Usage.tokens(stats.cache_read)} cached"
    ]
    |> Enum.filter(& &1)
    |> Enum.join(" · ")
  end

  defp stats_text(_stats), do: ""

  defp positive(value) when is_number(value) and value > 0, do: value
  defp positive(_value), do: nil

  defp present(index, kind, text) do
    case String.trim(text) do
      "" -> []
      trimmed -> [%{index: index, kind: kind, text: trimmed}]
    end
  end

  defp describe(%{name: name, arguments: arguments}) do
    "#{name} #{summarize(arguments)}"
  end

  defp fenced(code) do
    fence = String.duplicate("`", max(3, longest_backtick_run(code) + 1))
    fence <> "js\n" <> dedent(code) <> "\n" <> fence
  end

  defp longest_backtick_run(text) do
    ~r/`+/
    |> Regex.scan(text)
    |> Enum.map(fn [run] -> String.length(run) end)
    |> Enum.max(fn -> 0 end)
  end

  defp dedent(code) do
    lines =
      code
      |> String.trim_trailing()
      |> String.split(~r/\r?\n/)
      |> Enum.drop_while(&blank?/1)

    indent =
      lines
      |> Enum.reject(&blank?/1)
      |> Enum.map(&(String.length(&1) - String.length(String.trim_leading(&1))))
      |> Enum.min(fn -> 0 end)

    Enum.map_join(lines, "\n", &String.slice(&1, indent..-1//1))
  end

  defp blank?(line), do: String.trim(line) == ""

  defp summarize(arguments) when is_map(arguments) do
    case Enum.find_value(@summary_keys, &Map.get(arguments, &1)) do
      value when is_binary(value) -> value
      _none -> arguments |> JSON.encode!() |> clip()
    end
  end

  defp summarize(arguments) do
    arguments |> JSON.encode!() |> clip()
  end

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
