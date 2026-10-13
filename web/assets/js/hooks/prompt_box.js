export const PASTE_LINE_THRESHOLD = 4

export function normalizeLineEndings(text) {
  return text.replace(/\r\n/g, "\n").replace(/\r/g, "\n")
}

export function lineCount(text) {
  return text.split("\n").length
}

export function decide(pending, text, pasteCount) {
  if (pending && pending.content === text) {
    return {type: "expand", label: pending.label, text}
  }

  const count = lineCount(text)
  if (count <= PASTE_LINE_THRESHOLD) {
    return {type: "insert"}
  }

  const label = `[Pasted text #${pasteCount + 1} ${count} lines]`
  return {type: "placeholder", label, text, number: pasteCount + 1}
}

export function activeMentionStart(value, cursor) {
  for (let i = cursor - 1; i >= 0; i--) {
    if (value[i] === "@") return i
    if (/\s/.test(value[i])) return null
  }
  return null
}

export function isCommandTrigger(value) {
  return value === ":"
}

export function appendBlock(existing, block) {
  if (block === "") return existing
  return existing.trim() === "" ? block : `${existing.replace(/\s+$/, "")}\n\n${block}`
}

export function queueFor(event) {
  if (event.key !== "Enter" || event.shiftKey || event.metaKey) return null
  if (event.altKey || event.ctrlKey) return "follow_up"
  return "steer"
}

const PromptBox = {
  mounted() {
    this.pending = null // {label, content} | null
    this.placeholders = new Map() // label -> real content, substituted back in at submit time
    this.pasteCount = 0
    this.mentionStart = null // index of the active mention's "@" in the textarea, or null

    this.el.addEventListener("keydown", (event) => this.handleKeydown(event))
    this.el.addEventListener("paste", (event) => this.handlePaste(event))
    this.el.addEventListener("input", () => this.handleInput())

    this.handleEvent("mention_insert", ({text}) => this.insertMention(text))
    this.handleEvent("prompt_fill", ({text}) => this.fill(text))
  },

  fill(text) {
    const el = this.el
    el.value = appendBlock(el.value, text)
    el.selectionStart = el.selectionEnd = el.value.length
    el.focus()
  },

  handleKeydown(event) {
    if (this.mentionStart !== null && this.handleMentionKeydown(event)) return

    if (event.key === "Escape") {
      event.preventDefault()
      event.stopPropagation()
      this.el.blur()
      this.pushEvent("focus_chat_history", {})
      return
    }

    const queue = queueFor(event)
    if (queue === null) return

    event.preventDefault()
    this.el.value = this.resolvePlaceholders(this.el.value)
    this.el.form.elements.queue.value = queue
    this.el.form.requestSubmit()
  },

  handleMentionKeydown(event) {
    switch (event.key) {
      case "ArrowDown":
        event.preventDefault()
        this.pushEvent("mention_move", {delta: 1})
        return true
      case "ArrowUp":
        event.preventDefault()
        this.pushEvent("mention_move", {delta: -1})
        return true
      case "Enter":
      case "Tab":
        event.preventDefault()
        this.pushEvent("mention_select", {})
        return true
      case "Escape":
        event.preventDefault()
        event.stopPropagation() // otherwise key_router.js also forwards this Escape
        this.mentionStart = null
        this.pushEvent("mention_close", {})
        return true
      default:
        return false
    }
  },

  handleInput() {
    this.pending = null

    if (isCommandTrigger(this.el.value)) {
      this.el.value = ""
      return this.pushEvent("command_open", {})
    }

    this.updateMentionState()
  },

  updateMentionState() {
    const el = this.el
    const cursor = el.selectionStart

    if (cursor !== el.selectionEnd) return this.closeMention()

    const start = activeMentionStart(el.value, cursor)
    if (start === null) return this.closeMention()

    this.mentionStart = start
    this.pushEvent("mention_query", {query: el.value.slice(start + 1, cursor)})
  },

  closeMention() {
    if (this.mentionStart === null) return
    this.mentionStart = null
    this.pushEvent("mention_close", {})
  },

  insertMention(text) {
    if (this.mentionStart === null) return
    const el = this.el
    const cursor = el.selectionStart
    el.value = el.value.slice(0, this.mentionStart) + text + el.value.slice(cursor)
    const newCursor = this.mentionStart + text.length
    el.selectionStart = el.selectionEnd = newCursor
    this.mentionStart = null
  },

  handlePaste(event) {
    const clipboard = event.clipboardData || window.clipboardData
    const text = normalizeLineEndings(clipboard.getData("text/plain"))
    const decision = decide(this.pending, text, this.pasteCount)

    switch (decision.type) {
      case "expand":
        event.preventDefault()
        this.replaceLabel(decision.label, decision.text)
        this.placeholders.delete(decision.label)
        this.pending = null
        break

      case "placeholder":
        event.preventDefault()
        this.pasteCount = decision.number
        this.insertAtCursor(decision.label)
        this.placeholders.set(decision.label, decision.text)
        this.pending = {label: decision.label, content: decision.text}
        break

      case "insert":
        this.pending = null
        break
    }
  },

  resolvePlaceholders(value) {
    for (const [label, text] of this.placeholders) {
      value = value.split(label).join(text)
    }
    return value
  },

  insertAtCursor(text) {
    const el = this.el
    const start = el.selectionStart
    const end = el.selectionEnd
    el.value = el.value.slice(0, start) + text + el.value.slice(end)
    el.selectionStart = el.selectionEnd = start + text.length
  },

  replaceLabel(label, text) {
    const el = this.el
    const idx = el.value.indexOf(label)
    if (idx === -1) return
    el.value = el.value.slice(0, idx) + text + el.value.slice(idx + label.length)
    el.selectionStart = el.selectionEnd = idx + text.length
  },
}

export default PromptBox
