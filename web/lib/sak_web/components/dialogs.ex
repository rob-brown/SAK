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
