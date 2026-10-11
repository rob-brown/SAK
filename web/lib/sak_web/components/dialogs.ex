defmodule SakWeb.Dialogs do
  @moduledoc false

  use Phoenix.Component

  attr :confirm, :map, required: true

  def confirm(assigns) do
    ~H"""
    <div
      id="confirm-dialog"
      class="fixed inset-0 z-50 flex items-start justify-center bg-black/60 pt-20"
    >
      <div class="bg-neutral-900 border border-neutral-700 rounded-md w-[28rem] p-3 space-y-3">
        <p class="font-semibold truncate">{title(@confirm)}</p>
        <p class="text-xs text-neutral-500 break-all">{detail(@confirm)}</p>
        <div class="flex items-center gap-3 text-xs">
          <button
            id="confirm-yes"
            phx-click="confirm_accept"
            class={["hover:text-neutral-100", verb_color(@confirm.action)]}
          >
            enter {verb(@confirm.action)}
          </button>
          <button
            id="confirm-no"
            phx-click="confirm_cancel"
            class="text-neutral-400 hover:text-neutral-100"
          >
            esc cancel
          </button>
        </div>
      </div>
    </div>
    """
  end

  attr :form, :map, required: true

  def skill_form(assigns) do
    ~H"""
    <div
      id="skill-form-overlay"
      class="fixed inset-0 z-50 flex items-start justify-center bg-black/60 pt-20"
    >
      <form
        id="skill-form"
        phx-hook="SkillForm"
        phx-change="skill_change"
        phx-submit="skill_submit"
        class="bg-neutral-900 border border-neutral-700 rounded-md w-[40rem] max-h-[75vh] flex flex-col"
      >
        <div class="px-3 py-2 border-b border-neutral-800 shrink-0">
          <p class="font-semibold">Skill: {@form.skill["name"]}</p>
          <p class="text-xs text-neutral-500">{@form.skill["description"]}</p>
        </div>
        <div class="overflow-y-auto px-3 py-2 space-y-3">
          <div :for={{field, index} <- Enum.with_index(@form.fields)} id={"skill-field-#{field.name}"}>
            <label for={"skill-arg-#{field.name}"} class="text-xs text-neutral-400">
              {field.name}{if field.required?, do: " *"}
              <span :if={field.description} class="text-neutral-600">— {field.description}</span>
            </label>
            <input
              id={"skill-arg-#{field.name}"}
              type="text"
              name={"values[#{field.name}]"}
              value={field.value}
              data-current={to_string(index == @form.index)}
              autocomplete="off"
              class={[
                "w-full bg-neutral-950 text-neutral-100 px-2 py-1 outline-none border rounded",
                index == @form.index && "border-neutral-400",
                index != @form.index && "border-neutral-800"
              ]}
            />
          </div>
        </div>
        <p :if={@form.error} id="skill-form-error" class="px-3 pb-1 text-xs text-red-400">
          {@form.error}
        </p>
        <div class="px-3 py-2 border-t border-neutral-800 text-xs text-neutral-500 flex items-center gap-4 shrink-0">
          <span>[ ] switch field · enter next, or run on the last · ctrl-enter run now · esc cancel</span>
          <button
            id="skill-run"
            type="button"
            phx-click="skill_run"
            class="ml-auto text-green-400 hover:text-neutral-100"
          >
            run
          </button>
        </div>
      </form>
    </div>
    """
  end

  attr :picker, :map, required: true

  def mode_picker(assigns) do
    ~H"""
    <div
      id="mode-picker"
      class="fixed inset-0 z-50 flex items-start justify-center bg-black/60 pt-20"
    >
      <div class="bg-neutral-900 border border-neutral-700 rounded-md w-[40rem] flex flex-col">
        <div class="px-3 py-2 border-b border-neutral-800 font-semibold">
          Permissions for this session
        </div>
        <ul>
          <li
            :for={{mode, index} <- Enum.with_index(@picker.modes)}
            id={"mode-#{mode}"}
            data-selected={to_string(index == @picker.selected)}
            phx-click="mode_pick_index"
            phx-value-index={index}
            class={[
              "px-3 py-2 cursor-pointer",
              index == @picker.selected && "bg-neutral-800 text-neutral-100",
              index != @picker.selected && "text-neutral-400 hover:bg-neutral-800/60"
            ]}
          >
            <p>
              <span class="font-semibold">{mode}</span>
              <span :if={mode == @picker.current} class="ml-2 text-xs text-green-400">in use</span>
              <span :if={mode == @picker.default} class="ml-2 text-xs text-neutral-500">
                config default
              </span>
            </p>
            <p class="text-xs text-neutral-500">{mode_description(mode)}</p>
          </li>
        </ul>
        <p class="px-3 py-2 border-t border-neutral-800 text-xs text-neutral-500">
          j/k move · enter apply to this session and its subagents · esc cancel · deny rules always apply · lasts until the gateway restarts
        </p>
      </div>
    </div>
    """
  end

  defp mode_description("ask"),
    do: "Ask before bash, write and edit. Reads inside the working directory are allowed."

  defp mode_description("accept-edits"),
    do: "Allow write and edit inside the working directory. Still ask before bash."

  defp mode_description("auto"), do: "Allow everything that no deny rule blocks."
  defp mode_description(_mode), do: ""

  attr :request, :map, required: true
  attr :waiting, :integer, default: 0

  def permission(assigns) do
    ~H"""
    <div
      id="permission-dialog"
      tabindex="-1"
      phx-hook="AutoFocus"
      class="fixed inset-0 z-50 flex items-start justify-center bg-black/60 pt-20 outline-none"
    >
      <div class="bg-neutral-900 border border-yellow-700 rounded-md w-[40rem] p-3 space-y-3">
        <p class="font-semibold">Allow {@request["tool"]}?</p>
        <p :if={@request["subagent"]} id="permission-subagent" class="text-xs text-neutral-500">
          Requested by subagent #{@request["subagent"]}
        </p>
        <p :if={@request["note"]} id="permission-note" class="text-xs text-yellow-500">
          {@request["note"]}
        </p>
        <pre
          id="permission-summary"
          class="text-xs text-neutral-300 bg-neutral-950 border border-neutral-800 rounded p-2 whitespace-pre-wrap break-all max-h-60 overflow-auto"
        >{@request["summary"]}</pre>
        <p :if={@waiting > 0} class="text-xs text-neutral-500">{@waiting} more waiting</p>
        <div class="flex items-center gap-4 text-xs">
          <button
            id="permission-allow"
            phx-click="permission_answer"
            phx-value-approval="allow"
            class="text-green-400 hover:text-neutral-100"
          >
            y allow once
          </button>
          <button
            id="permission-allow-conversation"
            phx-click="permission_answer"
            phx-value-approval="allow_conversation"
            class="text-yellow-500 hover:text-neutral-100"
          >
            a allow this exact call for the session
          </button>
          <button
            id="permission-deny"
            phx-click="permission_answer"
            phx-value-approval="deny"
            class="text-red-400 hover:text-neutral-100"
          >
            n deny
          </button>
        </div>
      </div>
    </div>
    """
  end

  attr :rename, :map, required: true

  def rename(assigns) do
    ~H"""
    <div
      id="rename-overlay"
      class="fixed inset-0 z-50 flex items-start justify-center bg-black/60 pt-20"
    >
      <div class="bg-neutral-900 border border-neutral-700 rounded-md w-[36rem] flex flex-col">
        <div class="px-3 py-2 border-b border-neutral-800 font-semibold">Rename session</div>
        <form id="rename-form" phx-submit="rename_save" class="px-3 py-2">
          <input
            id="rename-input"
            type="text"
            name="name"
            value={@rename.name}
            phx-hook="AutoFocus"
            autocomplete="off"
            placeholder="Session name — leave blank to clear it"
            class="w-full bg-neutral-950 text-neutral-100 px-2 py-1 outline-none border border-neutral-800 rounded"
          />
        </form>
        <p class="px-3 py-2 border-t border-neutral-800 text-xs text-neutral-500">
          enter save · esc cancel
        </p>
      </div>
    </div>
    """
  end

  defp title(%{action: :delete, label: label}), do: "Delete session #{label}?"
  defp title(%{action: :archive, label: label}), do: "Archive session #{label}?"

  defp title(%{action: :fork, label: label, row: row}) do
    "Fork #{label} at entry #{row.number}?"
  end

  defp detail(%{action: :delete, cwd: cwd}) do
    "#{cwd}. It disappears from the list and cannot be brought back from Sak."
  end

  defp detail(%{action: :archive, cwd: cwd}) do
    "#{cwd}. It is hidden from the list. A shows archived sessions and R restores one."
  end

  defp detail(%{action: :fork, row: row}) do
    "A new session is created with the history up to and including entry #{row.number} (id #{row.id}). The original is unchanged."
  end

  defp verb(:delete), do: "delete"
  defp verb(:archive), do: "archive"
  defp verb(:fork), do: "fork"

  defp verb_color(:delete), do: "text-red-400"
  defp verb_color(_action), do: "text-yellow-500"
end
