defmodule SakWeb.WizardOverlay do
  @moduledoc false

  use Phoenix.Component

  import SakWeb.Overlays, only: [overlay: 1, row_classes: 1]

  alias Sak.NewSessionWizard

  attr :new_session, :map, required: true

  def wizard(assigns) do
    ~H"""
    <.overlay id="wizard-overlay">
      <.step wizard={@new_session.wizard} error={@new_session.error} />
    </.overlay>
    """
  end

  attr :wizard, :map, required: true
  attr :error, :string, default: nil

  defp step(assigns) do
    assigns =
      assign(assigns,
        candidates: NewSessionWizard.candidates(assigns.wizard),
        hidden: NewSessionWizard.hidden_count(assigns.wizard),
        breadcrumb: NewSessionWizard.breadcrumb(assigns.wizard)
      )

    ~H"""
    <div class="px-3 py-2 border-b border-neutral-800 shrink-0 flex items-center justify-between">
      <span class="font-semibold">New session — {title(@wizard.step)}</span>
      <span class="text-xs text-neutral-500">
        {NewSessionWizard.step_number(@wizard)}/{NewSessionWizard.step_count(@wizard)}
      </span>
    </div>

    <p
      :if={@breadcrumb != []}
      id="wizard-breadcrumb"
      class="px-3 pt-2 text-xs text-neutral-500 truncate"
    >
      {Enum.join(@breadcrumb, " › ")}
    </p>

    <form
      id="wizard-form"
      phx-change="wizard_query"
      phx-submit="wizard_accept"
      class="px-3 py-2 border-b border-neutral-800 shrink-0"
    >
      <input
        id={"wizard-input-#{@wizard.step}"}
        type="text"
        name="query"
        value={@wizard.query}
        phx-hook="WizardInput"
        phx-debounce="120"
        autocomplete="off"
        placeholder={placeholder(@wizard.step)}
        class="w-full bg-neutral-950 text-neutral-100 px-2 py-1 outline-none border border-neutral-800 rounded"
      />
    </form>

    <p :if={@error} id="wizard-error" class="px-3 pt-2 text-xs text-red-500">{@error}</p>
    <p
      :if={@wizard.step == :directory and @wizard.directories_loading?}
      class="px-3 pt-2 text-xs text-neutral-500"
    >
      searching directories…
    </p>

    <p :if={@wizard.step == :name} id="wizard-name-hint" class="px-3 py-3 text-neutral-500">
      Leave it blank to start the session unnamed.
    </p>

    <ul
      :if={@wizard.step != :name}
      id="wizard-candidates"
      phx-hook="ScrollSelected"
      class="overflow-y-auto p-1"
    >
      <li
        :for={{candidate, index} <- Enum.with_index(@candidates)}
        id={"wizard-candidate-#{index}"}
        data-selected={to_string(index == @wizard.selected)}
        phx-click="wizard_select_index"
        phx-value-index={index}
        class={row_classes(index == @wizard.selected)}
      >
        <span class="shrink-0">{candidate.label}</span>
        <span :if={Map.get(candidate, :detail, "") != ""} class="truncate text-xs text-neutral-500">
          {candidate.detail}
        </span>
        <span :if={badge(candidate)} class="ml-auto shrink-0 text-xs text-neutral-500">
          {badge(candidate)}
        </span>
      </li>
    </ul>

    <p :if={@hidden > 0} id="wizard-more" class="px-3 py-1 text-xs text-neutral-500 shrink-0">
      and {@hidden} more, keep typing to narrow
    </p>

    <p class="px-3 py-2 border-t border-neutral-800 text-xs text-neutral-500 shrink-0">
      {footer(@wizard.step)}
    </p>
    """
  end

  defp title(:directory), do: "Directory"
  defp title(:persona), do: "Persona"
  defp title(:model), do: "Model"
  defp title(:name), do: "Name (optional)"

  defp footer(:directory), do: "↑↓ move · enter accept · esc cancel"
  defp footer(:persona), do: "↑↓ move · enter accept · esc back"
  defp footer(:model), do: "↑↓ move · enter accept · esc back"
  defp footer(:name), do: "enter start · esc back"

  defp placeholder(:directory) do
    "Search directories — ~ for home, ../ to go up, or type a full path"
  end

  defp placeholder(:persona), do: "Search personas"
  defp placeholder(:model), do: "Search models"
  defp placeholder(:name), do: "Name this session, or press enter to leave it unnamed"

  defp badge(%{kind: :default}), do: "default"
  defp badge(%{kind: :project}), do: "project"
  defp badge(%{kind: :typed}), do: "typed path"
  defp badge(_candidate), do: nil
end
