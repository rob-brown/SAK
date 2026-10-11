export function fieldDelta(event) {
  if (event.ctrlKey || event.metaKey || event.altKey) return 0
  if (event.key === "[") return -1
  if (event.key === "]") return 1
  return 0
}

export function wantsRun(event) {
  return event.key === "Enter" && Boolean(event.ctrlKey || event.metaKey)
}

const SkillForm = {
  mounted() {
    this.onKeydown = (event) => {
      const delta = fieldDelta(event)
      if (delta !== 0) {
        event.preventDefault()
        this.pushEvent("skill_field", {delta})
      } else if (wantsRun(event)) {
        event.preventDefault()
        this.pushEvent("skill_run", {})
      }
    }
    this.el.addEventListener("keydown", this.onKeydown)
    this.focusCurrent()
  },

  updated() {
    this.focusCurrent()
  },

  destroyed() {
    this.el.removeEventListener("keydown", this.onKeydown)
  },

  focusCurrent() {
    const input = this.el.querySelector('input[data-current="true"]')
    if (input && document.activeElement !== input) input.focus()
  },
}

export default SkillForm
