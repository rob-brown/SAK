const ACTIONS = new Map([
  ["ArrowDown", {event: "wizard_move", payload: {delta: 1}}],
  ["ArrowUp", {event: "wizard_move", payload: {delta: -1}}],
  ["Enter", {event: "wizard_accept", payload: {}}],
  ["Escape", {event: "wizard_back", payload: {}}],
])

export function actionFor(key) {
  return ACTIONS.get(key) ?? null
}

const WizardInput = {
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

export default WizardInput
