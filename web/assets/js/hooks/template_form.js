export function tabDelta(event) {
  if (event.key !== "Tab") return 0
  if (event.ctrlKey || event.metaKey || event.altKey) return 0
  return event.shiftKey ? -1 : 1
}

export function wantsInsert(event) {
  return event.key === "Enter" && Boolean(event.ctrlKey || event.metaKey)
}

const TemplateForm = {
  mounted() {
    this.onKeydown = (event) => {
      const delta = tabDelta(event)
      if (delta !== 0) {
        event.preventDefault()
        this.pushEvent("template_field", {delta})
      } else if (wantsInsert(event)) {
        event.preventDefault()
        this.el.requestSubmit()
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
    const textarea = this.el.querySelector('textarea[data-current="true"]')
    if (textarea && document.activeElement !== textarea) textarea.focus()
  },
}

export default TemplateForm
