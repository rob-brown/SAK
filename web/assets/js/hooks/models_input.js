const ACTIONS = new Map([
  ["ArrowDown", {event: "models_move", payload: {delta: 1}}],
  ["ArrowUp", {event: "models_move", payload: {delta: -1}}],
  ["Enter", {event: "models_pick", payload: {}}],
  ["Escape", {event: "close_models", payload: {}}],
])

export function actionFor(key) {
  return ACTIONS.get(key) ?? null
}

const ModelsInput = {
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

export default ModelsInput
