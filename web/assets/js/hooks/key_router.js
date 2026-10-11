const NAMED_KEYS = {
  ArrowDown: "down",
  ArrowUp: "up",
  ArrowLeft: "left",
  ArrowRight: "right",
  Enter: "enter",
  Escape: "escape",
  Backspace: "backspace",
  Tab: "tab",
}

function isTextEntry(element) {
  if (!element) return false
  if (element.isContentEditable) return true
  const tag = element.tagName
  return tag === "TEXTAREA" || (tag === "INPUT" && element.type !== "checkbox" && element.type !== "radio")
}

function canonicalKey(event) {
  const named = NAMED_KEYS[event.key]
  if (named) return named
  if (event.key.length === 1) return event.key
  return event.key.toLowerCase()
}

function modifiers(event) {
  const mods = []
  if (event.ctrlKey) mods.push("ctrl")
  if (event.metaKey) mods.push("meta")
  if (event.altKey) mods.push("alt")
  if (event.shiftKey) mods.push("shift")
  return mods
}

const SCROLL_LINE = {j: 1, down: 1, k: -1, up: -1}
const SCROLL_HALF_PAGE = {"ctrl-d": 1, "ctrl-u": -1}
const LINE_PX = 24

export function scrollTargetId(dataset) {
  return dataset.subagentViewing === "true" ? "subagent-view" : "chat-history"
}

function scrollChat(dataset, deltaPx) {
  const el = document.getElementById(scrollTargetId(dataset))
  if (el) el.scrollTop += deltaPx
}

const SCROLL_EDGE = {g: "top", G: "bottom"}

function scrollChatToEdge(dataset, edge) {
  const el = document.getElementById(scrollTargetId(dataset))
  if (!el) return
  el.scrollTop = edge === "top" ? 0 : el.scrollHeight
}

function onlyShift(mods) {
  return mods.every((mod) => mod === "shift")
}

export function chatScrolls(dataset) {
  if (dataset.subagentViewing === "true") return true
  const serverTabs = ["entries", "subagents"]
  return (dataset.focusedPane || "chat_history") === "chat_history" && !serverTabs.includes(dataset.chatTab)
}

function focusedPane(root) {
  return root.dataset.focusedPane || "chat_history"
}

export function isModalOpen(dataset) {
  return (
    dataset.helpOpen === "true" ||
    dataset.modelsOpen === "true" ||
    dataset.confirmOpen === "true" ||
    dataset.permissionOpen === "true" ||
    dataset.modePickerOpen === "true" ||
    dataset.usageOpen === "true" ||
    dataset.renameOpen === "true" ||
    dataset.wizardOpen === "true" ||
    dataset.commandOpen === "true"
  )
}

export function modalKeys(dataset) {
  if (dataset.permissionOpen === "true") return ["escape", "y", "a", "n"]
  if (dataset.modePickerOpen === "true") return ["escape", "enter", "up", "down", "j", "k"]
  return dataset.confirmOpen === "true" ? ["escape", "enter"] : ["escape"]
}

function focusPromptTextarea() {
  const textarea = document.querySelector('textarea[phx-hook="PromptBox"]')
  if (textarea) textarea.focus()
}

const KeyRouter = {
  mounted() {
    this.handleKeydown = (event) => {
      const key = canonicalKey(event)
      const mods = modifiers(event)
      const target = event.target

      if (isTextEntry(target) && key !== "escape") return

      if (isModalOpen(this.el.dataset)) {
        if (modalKeys(this.el.dataset).includes(key)) {
          event.preventDefault()
          this.pushEvent("key", {key, modifiers: mods})
        }
        return
      }

      const pane = focusedPane(this.el)
      const scrollsChat = chatScrolls(this.el.dataset)

      if (key in SCROLL_LINE && mods.length === 0) {
        event.preventDefault()
        if (scrollsChat) {
          scrollChat(this.el.dataset, SCROLL_LINE[key] * LINE_PX)
        } else {
          this.pushEvent("key", {key, modifiers: mods})
        }
        return
      }

      const combo = mods.length === 1 ? `${mods[0]}-${key}` : key
      if (combo in SCROLL_HALF_PAGE) {
        event.preventDefault()
        if (scrollsChat) {
          const el = document.getElementById(scrollTargetId(this.el.dataset))
          const page = el ? el.clientHeight / 2 : 300
          scrollChat(this.el.dataset, SCROLL_HALF_PAGE[combo] * page)
        } else if (pane === "chat_history") {
          this.pushEvent("key", {key: combo, modifiers: []})
        }
        return
      }

      if (key in SCROLL_EDGE && onlyShift(mods) && scrollsChat) {
        event.preventDefault()
        scrollChatToEdge(this.el.dataset, SCROLL_EDGE[key])
        return
      }

      if (key === "enter" && mods.length === 0 && scrollsChat && this.el.dataset.subagentViewing !== "true") {
        event.preventDefault()
        focusPromptTextarea()
        return
      }

      event.preventDefault()
      this.pushEvent("key", {key, modifiers: mods})
    }

    window.addEventListener("keydown", this.handleKeydown)
  },

  destroyed() {
    window.removeEventListener("keydown", this.handleKeydown)
  },
}

export default KeyRouter
