defmodule SakWeb.ChatComponents do
  @moduledoc false

  use Phoenix.Component

  alias Sak.ChatFields
  alias Sak.Markdown

  attr :id, :string, required: true
  attr :item, :map, required: true
  attr :opts, :map, required: true
  attr :term, :string, default: ""
  attr :current, :any, default: nil

  def message(assigns) do
    assigns = assign(assigns, fields: ChatFields.fields(assigns.item, assigns.opts))

    ~H"""
    <div id={@id}>
      <div :for={field <- @fields} class={field_class(@item.role, field.kind)}>
        {Markdown.to_html(field.text, @term, current_occurrence(@current, @item.index, field.index))}
      </div>
    </div>
    """
  end

  defp current_occurrence({item, field, occurrence}, item, field), do: occurrence
  defp current_occurrence(_current, _item, _field), do: nil

  defp field_class(:user, _kind), do: "w-full px-3 py-2 bg-neutral-800 text-white chat-markdown"
  defp field_class(_role, :reasoning), do: "w-full px-3 py-1 text-cyan-400 chat-markdown"
  defp field_class(_role, :content), do: "w-full px-3 py-1 text-green-400 chat-markdown"
  defp field_class(_role, :error), do: "w-full px-3 py-1 text-red-400 chat-markdown"
  defp field_class(_role, :context), do: "w-full px-3 py-1 text-neutral-400 chat-markdown"
  defp field_class(_role, :stats), do: "w-full px-3 pb-1 text-xs text-neutral-600"

  defp field_class(_role, :code_call) do
    "w-full px-3 py-2 bg-[rgb(30,38,55)] text-fuchsia-400 chat-markdown code-call"
  end

  defp field_class(_role, :description) do
    "w-full px-3 py-2 bg-[rgb(30,38,55)] text-fuchsia-400 font-semibold chat-markdown"
  end

  defp field_class(_role, :tool_content) do
    "w-full px-3 pb-2 bg-[rgb(30,38,55)] text-fuchsia-400 chat-markdown"
  end
end
