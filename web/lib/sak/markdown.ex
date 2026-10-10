defmodule Sak.Markdown do
  @moduledoc """
  Renders markdown to HTML. Raw HTML in the input is never passed through
  (MDEx omits it unless `render: [unsafe: true]` is set, which is not done
  here), so the result is safe to mark as raw.
  """

  @extension [table: true, strikethrough: true, autolink: true, tasklist: true]

  def to_html(text) do
    text
    |> MDEx.to_html!(extension: @extension)
    |> Phoenix.HTML.raw()
  end
end
