defmodule SakWeb.Overlays do
  @moduledoc false

  use Phoenix.Component

  alias Sak.NewSessionWizard

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
        class="px-3 py-2 border-b border-neutral-800 shrink-0"
      >
        <input
          id="models-search-input"
          type="text"
          name="query"
          value={@models.query}
          phx-hook="AutoFocus"
          placeholder="Search models"
          autocomplete="off"
          class="w-full bg-neutral-950 text-neutral-100 px-2 py-1 outline-none border border-neutral-800 rounded"
        />
      </form>

      <p :if={@visible == []} id="models-empty" class="px-3 py-3 text-neutral-500">no matches</p>

      <ul id="models-list" class="overflow-y-auto p-1">
        <li
          :for={{id, index} <- Enum.with_index(@visible)}
          id={"model-#{index}"}
          class="px-2 py-1 flex gap-3"
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
    </.overlay>
    """
  end

  attr :new_session, :map, required: true

  def wizard(assigns) do
    ~H"""
    <.overlay id="wizard-overlay">
      <%= case @new_session.phase do %>
        <% :ready -> %>
          <.step wizard={@new_session.wizard} error={@new_session.error} />
        <% :submitting -> %>
          <div class="px-3 py-2 border-b border-neutral-800 font-semibold shrink-0">New session</div>
          <p id="wizard-submitting" class="px-3 py-3 text-neutral-500">starting session…</p>
      <% end %>
    </.overlay>
    """
  end

  attr :wizard, :map, required: true
  attr :error, :string, default: nil

  defp step(assigns) do
    assigns =
      assign(assigns,
        candidates: NewSessionWizard.candidates(assigns.wizard),
        hidden: NewSessionWizard.hidden_count(assigns.wizard)
      )

    ~H"""
    <div class="px-3 py-2 border-b border-neutral-800 shrink-0 flex items-center justify-between">
      <span class="font-semibold">New session — Directory</span>
      <span class="text-xs text-neutral-500">1/1</span>
    </div>

    <form
      id="wizard-form"
      phx-change="wizard_query"
      phx-submit="wizard_accept"
      class="px-3 py-2 border-b border-neutral-800 shrink-0"
    >
      <input
        id="wizard-input"
        type="text"
        name="query"
        value={@wizard.query}
        phx-hook="WizardInput"
        phx-debounce="120"
        autocomplete="off"
        placeholder="Search directories — ~ for home, ../ to go up, or type a full path"
        class="w-full bg-neutral-950 text-neutral-100 px-2 py-1 outline-none border border-neutral-800 rounded"
      />
    </form>

    <p :if={@error} id="wizard-error" class="px-3 pt-2 text-xs text-red-500">{@error}</p>
    <p :if={@wizard.directories_loading?} class="px-3 pt-2 text-xs text-neutral-500">
      searching directories…
    </p>

    <ul id="wizard-candidates" phx-hook="ScrollSelected" class="overflow-y-auto p-1">
      <li
        :for={{candidate, index} <- Enum.with_index(@candidates)}
        id={"wizard-candidate-#{index}"}
        data-selected={to_string(index == @wizard.selected)}
        phx-click="wizard_select_index"
        phx-value-index={index}
        class={row_classes(index == @wizard.selected)}
      >
        <span class="truncate">{candidate.label}</span>
        <span :if={badge(candidate)} class="ml-auto shrink-0 text-xs text-neutral-500">
          {badge(candidate)}
        </span>
      </li>
    </ul>

    <p :if={@hidden > 0} id="wizard-more" class="px-3 py-1 text-xs text-neutral-500 shrink-0">
      and {@hidden} more, keep typing to narrow
    </p>

    <p class="px-3 py-2 border-t border-neutral-800 text-xs text-neutral-500 shrink-0">
      ↑↓ move · enter accept · esc cancel
    </p>
    """
  end

  slot :inner_block, required: true
  attr :id, :string, required: true

  defp overlay(assigns) do
    ~H"""
    <div id={@id} class="fixed inset-0 z-50 flex items-start justify-center bg-black/60 pt-20">
      <div class="bg-neutral-900 border border-neutral-700 rounded-md w-[36rem] max-h-[75vh] flex flex-col">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  defp row_classes(selected?) do
    [
      "px-2 py-1 flex gap-3 items-baseline cursor-pointer hover:bg-neutral-800",
      selected? && "bg-neutral-800 ring-1 ring-inset ring-neutral-500"
    ]
  end

  defp badge(%{kind: :default}), do: "default"
  defp badge(%{kind: :project}), do: "project"
  defp badge(%{kind: :typed}), do: "typed path"
  defp badge(_candidate), do: nil
end
