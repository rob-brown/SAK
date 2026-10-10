export function actionFor(event) {
  if (event.isComposing) return "none"
  if (event.key === "Escape") return "blur"
  if (event.key === "Enter" && !event.shiftKey) return "submit"
  return "none"
}

export const PromptBox = {
  mounted() {
    this.el.addEventListener("keydown", (event) => {
      const action = actionFor(event)
      if (action === "none") return
      event.preventDefault()
      event.stopPropagation()
      if (action === "blur") this.el.blur()
      if (action === "submit" && this.el.value.trim() !== "") this.el.form.requestSubmit()
    })

    this.el.form.addEventListener("submit", () => {
      requestAnimationFrame(() => {
        this.el.value = ""
      })
    })
  },
}
