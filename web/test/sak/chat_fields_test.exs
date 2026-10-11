defmodule Sak.ChatFieldsTest do
  use ExUnit.Case, async: true

  alias Sak.ChatFields
  alias Sak.Markdown

  @opts %{thinking_visible?: true, tool_output_visible?: false}

  defp codemode_item(code) do
    %{
      index: 0,
      role: :assistant,
      blocks: [%{type: :tool_call, name: "codemode", arguments: %{"code" => code}}]
    }
  end

  defp rendered(code) do
    [field] = ChatFields.fields(codemode_item(code), @opts)
    {:safe, html} = Markdown.to_html(field.text)
    {field, IO.iodata_to_binary(html)}
  end

  test "a codemode call is a header followed by the code with real line breaks" do
    # Arrange
    code = "const out = await tools.bash({ command: 'ls' });\ntext(out);\nreturn 1;"

    # Act
    {field, html} = rendered(code)

    # Assert
    assert field.kind == :code_call
    assert field.text == "codemode\n\n```js\n#{code}\n```"
    assert html =~ "<p>codemode</p>"
    assert html =~ "text(out);\nreturn 1;"
    refute html =~ "\\n"
  end

  test "common leading indentation is removed and relative indentation is kept" do
    # Arrange
    code = "\n    if (ok) {\n      go();\n    }\n    done();\n  "

    # Act
    {field, _html} = rendered(code)

    # Assert
    assert field.text == "codemode\n\n```js\nif (ok) {\n  go();\n}\ndone();\n```"
  end

  test "blank lines inside the script survive and do not count towards the indentation" do
    # Arrange
    code = "  a();\n\n    b();"

    # Act
    {field, _html} = rendered(code)

    # Assert
    assert field.text == "codemode\n\n```js\na();\n\n  b();\n```"
  end

  test "the fence grows when the code itself contains backticks" do
    # Arrange
    code = "text(`inline ``` fence`);"

    # Act
    {field, html} = rendered(code)

    # Assert
    assert String.starts_with?(field.text, "codemode\n\n````js\n")
    assert String.ends_with?(field.text, "\n````")
    assert html =~ "inline ``` fence"
  end

  test "other tool calls keep their one-line description" do
    # Arrange
    item = %{
      index: 0,
      role: :assistant,
      blocks: [%{type: :tool_call, name: "bash", arguments: %{"command" => "ls -la"}}]
    }

    # Act
    [field] = ChatFields.fields(item, @opts)

    # Assert
    assert {field.kind, field.text} == {:description, "bash ls -la"}
  end

  test "a codemode call without code falls back to the generic description" do
    # Arrange
    item = %{
      index: 0,
      role: :assistant,
      blocks: [%{type: :tool_call, name: "codemode", arguments: %{}}]
    }

    # Act
    [field] = ChatFields.fields(item, @opts)

    # Assert
    assert field.kind == :description
  end

  test "stats show only when asked for: model time and tokens under a reply, name and time under a tool result" do
    # Arrange
    reply = %{
      index: 0,
      role: :assistant,
      blocks: [%{type: :text, text: "done"}],
      stats: %{kind: :model, ms: 1_840, input: 1_234, output: 56, cache_read: 1_000}
    }

    result = %{
      index: 1,
      role: :tool_result,
      blocks: [%{type: :tool_result, name: "bash", text: "out", error?: false}],
      stats: %{kind: :tool, name: "bash", ms: 120}
    }

    shown = Map.put(@opts, :stats_visible?, true)

    # Act
    hidden_fields = ChatFields.fields(reply, @opts)
    reply_fields = ChatFields.fields(reply, shown)
    result_fields = ChatFields.fields(result, shown)

    # Assert
    assert Enum.map(hidden_fields, & &1.kind) == [:content]

    assert List.last(reply_fields) == %{
             index: 2,
             kind: :stats,
             text: "1.8 s · 1,234 in · 56 out · 1,000 cached"
           }

    assert List.last(result_fields).text == "bash · 120 ms"
  end

  test "a tool result without a recorded time and a reply without usage add no stats line" do
    # Arrange
    shown = Map.put(@opts, :stats_visible?, true)

    untimed = %{
      index: 0,
      role: :tool_result,
      blocks: [],
      stats: %{kind: :tool, name: "bash", ms: nil}
    }

    bare = %{
      index: 1,
      role: :assistant,
      blocks: [],
      stats: %{kind: :model, ms: nil, input: nil, output: nil, cache_read: nil}
    }

    # Act
    fields = ChatFields.fields(untimed, shown) ++ ChatFields.fields(bare, shown)

    # Assert
    assert fields == []
  end
end
