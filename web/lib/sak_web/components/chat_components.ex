defmodule SakWeb.ChatComponents do
  @moduledoc false

  use Phoenix.Component

  attr :id, :string, required: true
  attr :item, :map, required: true

  def message(assigns) do
    ~H"""
    <article id={@id} class={message_classes(@item.role)}>
      <.block :for={block <- @item.blocks} block={block} markdown?={@item.role == :assistant} />
      <p :if={Map.get(@item, :error)} class="mt-2 text-sm text-red-400">
        {Map.get(@item, :error)}
      </p>
    </article>
    """
  end

  attr :block, :map, required: true
  attr :markdown?, :boolean, default: false

  def block(%{block: %{type: :text}, markdown?: true} = assigns) do
    ~H"""
    <div class="chat-markdown break-words">{Sak.Markdown.to_html(@block.text)}</div>
    """
  end

  def block(%{block: %{type: :text}} = assigns) do
    ~H"""
    <div class="whitespace-pre-wrap break-words">{@block.text}</div>
    """
  end

  def block(%{block: %{type: :thinking}} = assigns) do
    ~H"""
    <details class="my-1 text-sm text-neutral-500">
      <summary class="cursor-pointer select-none">thinking</summary>
      <div class="mt-1 whitespace-pre-wrap break-words italic">{@block.text}</div>
    </details>
    """
  end

  def block(%{block: %{type: :tool_call}} = assigns) do
    ~H"""
    <div class="my-1 rounded border border-neutral-800 bg-neutral-900 px-3 py-2 text-sm">
      <span class="font-semibold text-cyan-400">{@block.name}</span>
      <pre class="mt-1 max-h-48 overflow-auto whitespace-pre-wrap break-all text-neutral-400">{format_arguments(@block.arguments)}</pre>
    </div>
    """
  end

  def block(%{block: %{type: :tool_result}} = assigns) do
    ~H"""
    <div class="text-sm">
      <span class={[
        "font-semibold",
        @block.error? && "text-red-400",
        !@block.error? && "text-emerald-400"
      ]}>
        {@block.name}
      </span>
      <pre class="mt-1 max-h-64 overflow-auto whitespace-pre-wrap break-all text-neutral-400">{@block.text}</pre>
    </div>
    """
  end

  def block(assigns) do
    ~H"""
    <div class="text-sm text-neutral-500">{Map.get(@block, :text, "")}</div>
    """
  end

  defp message_classes(:user) do
    "border-l-2 border-cyan-500 bg-neutral-900 px-4 py-3"
  end

  defp message_classes(:tool_result) do
    "px-4 py-2 opacity-90"
  end

  defp message_classes(_role) do
    "px-4 py-3"
  end

  defp format_arguments(arguments) do
    JSON.encode!(arguments)
  end
end
