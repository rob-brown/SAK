defmodule Sak.Markdown do
  @moduledoc """
  Renders markdown to HTML. Raw HTML in the input is never passed through
  (MDEx omits it unless `render: [unsafe: true]` is set, which is not done
  here), so the result is safe to mark as raw.

  Search matches are wrapped in private-use sentinels before rendering and
  swapped for `<mark>` tags afterwards, so they cannot interact with the
  markdown syntax around them.
  """

  @extension [table: true, strikethrough: true, autolink: true, tasklist: true]

  @match_open "\u{E000}"
  @current_open "\u{E001}"
  @close "\u{E002}"

  def to_html(text, term \\ nil, current_occurrence \\ nil)

  def to_html(text, term, current_occurrence) when term not in [nil, ""] do
    text
    |> mark_occurrences(term, current_occurrence)
    |> render()
    |> replace_sentinels()
    |> Phoenix.HTML.raw()
  end

  def to_html(text, _term, _current_occurrence) do
    text |> render() |> Phoenix.HTML.raw()
  end

  defp render(text) do
    text
    |> MDEx.parse_document!(extension: @extension)
    |> MDEx.traverse_and_update(&html_block_as_code/1)
    |> MDEx.to_html!(render: [escape: true])
  end

  defp html_block_as_code(%MDEx.HtmlBlock{literal: literal}) do
    %MDEx.CodeBlock{literal: literal}
  end

  defp html_block_as_code(node), do: node

  defp mark_occurrences(text, term, current_occurrence) do
    do_mark(text, String.downcase(text), String.downcase(term), current_occurrence, 0, 0, [])
  end

  defp do_mark(text, downcased, term, current, offset, occurrence, acc) do
    remaining = binary_part(downcased, offset, byte_size(downcased) - offset)

    case :binary.match(remaining, term) do
      :nomatch ->
        acc |> prepend(text, offset, byte_size(text)) |> Enum.reverse() |> Enum.join()

      {relative_start, length} ->
        start = offset + relative_start
        open = if occurrence == current, do: @current_open, else: @match_open
        wrapped = open <> binary_part(text, start, length) <> @close
        acc = acc |> prepend(text, offset, start) |> then(&[wrapped | &1])
        do_mark(text, downcased, term, current, start + length, occurrence + 1, acc)
    end
  end

  defp prepend(acc, _text, from, to) when to <= from, do: acc

  defp prepend(acc, text, from, to) do
    [binary_part(text, from, to - from) | acc]
  end

  defp replace_sentinels(html) do
    html
    |> String.replace(@current_open, ~s(<mark class="chat-match chat-match-current">))
    |> String.replace(@match_open, ~s(<mark class="chat-match">))
    |> String.replace(@close, "</mark>")
  end
end
