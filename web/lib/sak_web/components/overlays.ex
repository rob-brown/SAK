defmodule SakWeb.Overlays do
  @moduledoc false

  use Phoenix.Component

  attr :rows, :list, required: true
  attr :search, :string, required: true

  def help(assigns) do
    ~H"""
    <.overlay id="help-overlay">
      <div class="px-3 py-2 border-b border-neutral-800 flex items-center justify-between shrink-0">
        <span class="font-semibold">Keybindings</span>
        <button phx-click="close_help" class="text-neutral-400 hover:text-neutral-100">esc</button>
      </div>

      <form
        id="help-search-form"
        phx-change="help_search"
        class="px-3 py-2 border-b border-neutral-800 shrink-0"
      >
        <input
          id="help-search-input"
          type="text"
          name="query"
          value={@search}
          phx-hook="AutoFocus"
          placeholder="Search descriptions — prepend @ to search by exact key"
          autocomplete="off"
          class="w-full bg-neutral-950 text-neutral-100 px-2 py-1 outline-none border border-neutral-800 rounded"
        />
      </form>

      <ul id="help-rows" class="overflow-y-auto p-2 space-y-0.5">
        <%= for row <- @rows do %>
          <%= case row do %>
            <% {:header, name} -> %>
              <li class="px-1 pt-2 pb-1 text-blue-400 font-semibold">{name}</li>
            <% :blank -> %>
            <% {:binding, {key, description}} -> %>
              <li class="px-1 py-0.5 flex gap-3">
                <span class="text-neutral-400 w-28 shrink-0">{key}</span>
                <span>{description}</span>
              </li>
          <% end %>
        <% end %>
      </ul>
    </.overlay>
    """
  end

  attr :query, :string, required: true
  attr :results, :list, required: true
  attr :selected, :integer, required: true

  def command(assigns) do
    ~H"""
    <.overlay id="command-overlay">
      <div class="px-3 py-2 border-b border-neutral-800 font-semibold shrink-0">Command</div>

      <form
        id="command-form"
        phx-change="command_query"
        phx-submit="command_run"
        class="px-3 py-2 border-b border-neutral-800 shrink-0"
      >
        <input
          id="command-input"
          type="text"
          name="query"
          value={@query}
          phx-hook="CommandInput"
          phx-debounce="120"
          autocomplete="off"
          placeholder="Search commands"
          class="w-full bg-neutral-950 text-neutral-100 px-2 py-1 outline-none border border-neutral-800 rounded"
        />
      </form>

      <p :if={@results == []} id="command-empty" class="px-3 py-3 text-neutral-500">no matches</p>

      <ul id="command-candidates" phx-hook="ScrollSelected" class="overflow-y-auto p-1">
        <li
          :for={{command, index} <- Enum.with_index(@results)}
          id={"command-candidate-#{index}"}
          data-selected={to_string(index == @selected)}
          phx-click="command_run_index"
          phx-value-index={index}
          class={row_classes(index == @selected)}
        >
          <span class="shrink-0">{command.name}</span>
          <span :if={command.aliases != []} class="shrink-0 text-xs text-neutral-500">
            also: {Enum.join(command.aliases, ", ")}
          </span>
          <span class="ml-auto truncate text-xs text-neutral-500">{command.description}</span>
        </li>
      </ul>

      <p class="px-3 py-2 border-t border-neutral-800 text-xs text-neutral-500 shrink-0">
        ↑↓ move · enter run · esc close
      </p>
    </.overlay>
    """
  end

  attr :models, :map, required: true
  attr :conversation_model, :string, default: nil
  attr :has_conversation?, :boolean, default: false

  def models(assigns) do
    assigns = assign(assigns, visible: SakWeb.ChatLive.Models.visible(assigns.models))

    ~H"""
    <.overlay id="models-overlay">
      <div class="px-3 py-2 border-b border-neutral-800 flex items-center justify-between shrink-0">
        <span class="font-semibold">Models</span>
        <button phx-click="close_models" class="text-neutral-400 hover:text-neutral-100">esc</button>
      </div>

      <div class="px-3 py-2 border-b border-neutral-800 text-xs text-neutral-400 shrink-0 space-y-0.5">
        <p>
          gateway default: <span id="models-default" class="text-neutral-100">{@models.current}</span>
        </p>
        <p :if={@conversation_model}>
          this conversation:
          <span id="models-conversation" class="text-neutral-100">{@conversation_model}</span>
        </p>
      </div>

      <form
        id="models-search-form"
        phx-change="models_search"
        phx-submit="models_pick"
        class="px-3 py-2 border-b border-neutral-800 shrink-0"
      >
        <input
          id="models-search-input"
          type="text"
          name="query"
          value={@models.query}
          phx-hook="ModelsInput"
          phx-debounce="120"
          placeholder="Search models"
          autocomplete="off"
          class="w-full bg-neutral-950 text-neutral-100 px-2 py-1 outline-none border border-neutral-800 rounded"
        />
      </form>

      <p :if={@visible == []} id="models-empty" class="px-3 py-3 text-neutral-500">no matches</p>

      <ul id="models-list" phx-hook="ScrollSelected" class="overflow-y-auto p-1">
        <li
          :for={{id, index} <- Enum.with_index(@visible)}
          id={"model-#{index}"}
          data-selected={to_string(index == @models.selected)}
          phx-click="models_pick_index"
          phx-value-index={index}
          class={row_classes(index == @models.selected)}
        >
          <span class="truncate">{id}</span>
          <span
            :if={String.ends_with?(@models.current || "", "/" <> id)}
            class="ml-auto shrink-0 text-xs text-green-400"
          >
            in use
          </span>
        </li>
      </ul>

      <p class="px-3 py-2 border-t border-neutral-800 text-xs text-neutral-500 shrink-0">
        {models_footer(@has_conversation?)}
      </p>
    </.overlay>
    """
  end

  slot :inner_block, required: true
  attr :id, :string, required: true

  def overlay(assigns) do
    ~H"""
    <div id={@id} class="fixed inset-0 z-50 flex items-start justify-center bg-black/60 pt-20">
      <div class="bg-neutral-900 border border-neutral-700 rounded-md w-[36rem] max-h-[75vh] flex flex-col">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  def row_classes(selected?) do
    [
      "px-2 py-1 flex gap-3 items-baseline cursor-pointer hover:bg-neutral-800",
      selected? && "bg-neutral-800 ring-1 ring-inset ring-neutral-500"
    ]
  end

  defp models_footer(true), do: "↑↓ move · enter use for this session · esc close"
  defp models_footer(false), do: "↑↓ move · enter use for new sessions · esc close"
end
