defmodule Sak.MarkdownTest do
  use ExUnit.Case, async: true

  alias Sak.Markdown

  defp render(text) do
    text |> Markdown.to_html() |> Phoenix.HTML.safe_to_string()
  end

  test "raw HTML is never passed through" do
    # Arrange
    text = "hello <script>alert(1)</script> <img src=x onerror=alert(1)>"

    # Act
    html = render(text)

    # Assert
    refute html =~ "<script"
    refute html =~ "<img"
    refute html =~ "onerror="
  end

  test "javascript links lose their href" do
    # Arrange
    text = "[click](javascript:alert(1))"

    # Act
    html = render(text)

    # Assert
    refute html =~ "javascript:"
  end

  test "renders tables, fenced code and emphasis" do
    # Arrange
    text = "| a | b |\n|---|--:|\n| 1 | 2 |\n\n**bold**\n\n```elixir\nIO.puts(1)\n```"

    # Act
    html = render(text)

    # Assert
    assert html =~ "<table>"
    assert html =~ "<strong>bold</strong>"
    assert html =~ ~s(<code class="language-elixir">)
  end
end
