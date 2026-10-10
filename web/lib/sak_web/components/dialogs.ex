defmodule SakWeb.Dialogs do
  @moduledoc false

  use Phoenix.Component

  attr :confirm, :map, required: true

  def confirm_delete(assigns) do
    ~H"""
    <div
      id="delete-confirm"
      class="fixed inset-0 z-50 flex items-start justify-center bg-black/60 pt-20"
    >
      <div class="bg-neutral-900 border border-neutral-700 rounded-md w-[28rem] p-3 space-y-3">
        <p class="font-semibold truncate">Delete session {@confirm.label}?</p>
        <p class="text-xs text-neutral-500 break-all">
          {@confirm.cwd}. It disappears from the list and cannot be brought back from Sak.
        </p>
        <div class="flex items-center gap-3 text-xs">
          <button
            id="delete-confirm-yes"
            phx-click="delete_confirm"
            class="text-red-400 hover:text-red-300"
          >
            enter delete
          </button>
          <button
            id="delete-confirm-no"
            phx-click="delete_cancel"
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
end
