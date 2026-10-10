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

function scrollChat(deltaPx) {
  const el = document.getElementById("chat-history")
  if (el) el.scrollTop += deltaPx
}

const SCROLL_EDGE = {g: "top", G: "bottom"}

function scrollChatToEdge(edge) {
  const el = document.getElementById("chat-history")
  if (!el) return
  el.scrollTop = edge === "top" ? 0 : el.scrollHeight
}

function onlyShift(mods) {
  return mods.every((mod) => mod === "shift")
}

function focusedPane(root) {
  return root.dataset.focusedPane || "chat_history"
}

export function isModalOpen(dataset) {
  return (
    dataset.helpOpen === "true" ||
    dataset.wizardOpen === "true" ||
    dataset.commandOpen === "true"
  )
}

export function modalKeys(_dataset) {
  return ["escape"]
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

      if (key in SCROLL_LINE && mods.length === 0) {
        event.preventDefault()
        if (pane === "chat_history") {
          scrollChat(SCROLL_LINE[key] * LINE_PX)
        } else {
          this.pushEvent("key", {key, modifiers: mods})
        }
        return
      }

      const combo = mods.length === 1 ? `${mods[0]}-${key}` : key
      if (combo in SCROLL_HALF_PAGE) {
        event.preventDefault()
        if (pane === "chat_history") {
          const el = document.getElementById("chat-history")
          const page = el ? el.clientHeight / 2 : 300
          scrollChat(SCROLL_HALF_PAGE[combo] * page)
        }
        return
      }

      if (key in SCROLL_EDGE && onlyShift(mods) && pane === "chat_history") {
        event.preventDefault()
        scrollChatToEdge(SCROLL_EDGE[key])
        return
      }

      if (key === "enter" && mods.length === 0 && pane === "chat_history") {
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
