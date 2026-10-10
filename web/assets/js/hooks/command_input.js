const ACTIONS = new Map([
  ["ArrowDown", {event: "command_move", payload: {delta: 1}}],
  ["ArrowUp", {event: "command_move", payload: {delta: -1}}],
  ["Enter", {event: "command_run", payload: {}}],
  ["Escape", {event: "command_close", payload: {}}],
])

export function actionFor(key) {
  return ACTIONS.get(key) ?? null
}

const CommandInput = {
  mounted() {
    this.el.focus()

    this.el.addEventListener("keydown", (event) => {
      if (event.isComposing) return

      if (event.key === "Tab") {
        event.preventDefault()
        return
      }

      const action = actionFor(event.key)
      if (action === null) return

      event.preventDefault()
      event.stopPropagation()
      this.pushEvent(action.event, action.payload)
    })
  },
}

export default CommandInput
