defmodule Sak.EntryRows do
  @moduledoc """
  One summary row per raw history entry, for the Entries tab: every entry
  the conversation stores, including system entries and tool results. The
  `number` is the entry's position in the history; `id` is the storage id
  that forking needs.
  """

  @text_limit 300
  @summary_keys ["command", "path", "file_path", "code"]

  @type row :: %{
          number: pos_integer(),
          id: integer(),
          label: String.t(),
          text: String.t(),
          record: map()
        }

  @spec rows([map()]) :: [row()]
  def rows(records) do
    records
    |> Enum.with_index(1)
    |> Enum.map(fn {record, number} ->
      %{
        number: number,
        id: record["id"],
        label: label(record["kind"]),
        text: record |> row_text() |> one_line(),
        record: record
      }
    end)
  end

  @spec detail(map()) :: String.t()
  def detail(%{"kind" => "sak.judge", "data" => data}) do
    Jason.encode!(data, pretty: true)
  end

  def detail(record) do
    Jason.encode!(messages(record), pretty: true)
  end

  defp row_text(%{"kind" => "sak.judge", "data" => data}) do
    percent =
      if is_number(data["probability"]), do: " (#{round(data["probability"] * 100)}%)", else: ""

    "#{data["purpose"]}: #{data["outcome"]}#{percent} · #{data["model"]}, #{data["ms"]} ms"
  end

  defp row_text(record) do
    record |> messages() |> Enum.map_join(" ", &summary/1)
  end

  defp messages(record) do
    Map.get(record, "model", [])
  end

  defp label("pi.user"), do: "user"
  defp label("pi.assistant"), do: "assistant"
  defp label("pi.tool-result"), do: "tool"
  defp label("pi.system"), do: "system"
  defp label("sak.judge"), do: "judge"
  defp label("pi." <> other), do: other
  defp label(other) when is_binary(other), do: other
  defp label(_kind), do: "entry"

  defp summary(%{"role" => "user", "content" => content}) do
    content_text(content)
  end

  defp summary(%{"role" => "assistant", "content" => content}) do
    assistant_text(List.wrap(content))
  end

  defp summary(%{"role" => "toolResult"} = message) do
    mark = if message["isError"] == true, do: "error ", else: ""
    "#{mark}#{message["toolName"]}: #{content_text(message["content"])}"
  end

  defp summary(%{"role" => "system"} = message) do
    system_text(message)
  end

  defp summary(message) do
    inspect(message, limit: 8, printable_limit: 120)
  end

  defp assistant_text(blocks) do
    text = blocks |> Enum.filter(&(&1["type"] == "text")) |> Enum.map_join(" ", & &1["text"])
    calls = Enum.filter(blocks, &(&1["type"] == "toolCall"))

    thinking =
      blocks |> Enum.filter(&(&1["type"] == "thinking")) |> Enum.map_join(" ", & &1["thinking"])

    cond do
      String.trim(text) != "" -> text <> call_suffix(calls)
      calls != [] -> Enum.map_join(calls, " · ", &describe_call/1)
      true -> "(thinking) " <> thinking
    end
  end

  defp call_suffix([]), do: ""

  defp call_suffix(calls) do
    " (+#{length(calls)} tool call#{plural(calls)})"
  end

  defp plural([_one]), do: ""
  defp plural(_many), do: "s"

  defp describe_call(%{"name" => name, "arguments" => arguments}) do
    "→ #{name} #{argument_summary(arguments)}"
  end

  defp describe_call(%{"name" => name}) do
    "→ #{name}"
  end

  defp argument_summary(arguments) when is_map(arguments) do
    case Enum.find_value(@summary_keys, &Map.get(arguments, &1)) do
      value when is_binary(value) -> value
      _none -> Jason.encode!(arguments)
    end
  end

  defp argument_summary(arguments) do
    inspect(arguments)
  end

  defp system_text(message) do
    content = message |> Map.get("content", "") |> content_text() |> String.trim()
    added = tool_names(message["toolsAdded"], "tools added")
    removed = tool_names(message["toolsRemoved"], "tools removed")

    case Enum.reject([content, added, removed], &(&1 == "")) do
      [] -> "(empty system message)"
      parts -> Enum.join(parts, " · ")
    end
  end

  defp tool_names(tools, label) when is_list(tools) and tools != [] do
    names = Enum.map_join(tools, ", ", &tool_name/1)
    "#{label}: #{names}"
  end

  defp tool_names(_tools, _label), do: ""

  defp tool_name(%{"name" => name}), do: name
  defp tool_name(name) when is_binary(name), do: name
  defp tool_name(_other), do: "?"

  defp content_text(content) when is_binary(content), do: content

  defp content_text(content) when is_list(content) do
    Enum.map_join(content, " ", fn
      %{"text" => text} -> text
      %{"type" => type} -> "[#{type}]"
      _other -> ""
    end)
  end

  defp content_text(_content), do: ""

  defp one_line(text) do
    text
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> String.slice(0, @text_limit)
  end
end
