const LINE_PX = 48

export function isTextEntry(el) {
  if (!el) return false
  return el.isContentEditable || ["INPUT", "TEXTAREA", "SELECT"].includes(el.tagName)
}

export function actionFor(event) {
  if (event.metaKey || event.altKey) return {type: "none"}
  if (event.ctrlKey) return ctrlAction(event.key)
  switch (event.key) {
    case "j": return {type: "scroll", lines: 1}
    case "k": return {type: "scroll", lines: -1}
    case "g": return {type: "scroll-edge", edge: "top"}
    case "G": return {type: "scroll-edge", edge: "bottom"}
    case "i": return {type: "focus", target: "prompt-input"}
    case "n": return {type: "focus", target: "new-session-cwd"}
    default: return {type: "none"}
  }
}

function ctrlAction(key) {
  if (key === "d") return {type: "scroll-page", direction: 1}
  if (key === "u") return {type: "scroll-page", direction: -1}
  return {type: "none"}
}

export const KeyRouter = {
  mounted() {
    this.onKeydown = (event) => {
      if (isTextEntry(document.activeElement)) return
      const action = actionFor(event)
      if (action.type === "none") return
      event.preventDefault()
      this.run(action)
    }
    window.addEventListener("keydown", this.onKeydown)
  },

  destroyed() {
    window.removeEventListener("keydown", this.onKeydown)
  },

  run(action) {
    const history = document.getElementById("chat-history")
    if (action.type === "scroll") history.scrollBy({top: action.lines * LINE_PX})
    if (action.type === "scroll-page") history.scrollBy({top: (action.direction * history.clientHeight) / 2})
    if (action.type === "scroll-edge") history.scrollTo({top: action.edge === "top" ? 0 : history.scrollHeight})
    if (action.type === "focus") document.getElementById(action.target)?.focus()
  },
}
