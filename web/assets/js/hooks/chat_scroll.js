const BOTTOM_THRESHOLD_PX = 80

export function isNearBottom(el) {
  return el.scrollHeight - el.scrollTop - el.clientHeight <= BOTTOM_THRESHOLD_PX
}

export const ChatScroll = {
  mounted() {
    this.pinned = true
    this.el.addEventListener("scroll", () => {
      this.pinned = isNearBottom(this.el)
    })
    this.observer = new MutationObserver(() => {
      if (this.pinned) this.scrollToBottom()
    })
    this.observer.observe(this.el, {childList: true, subtree: true, characterData: true})
    this.scrollToBottom()
  },

  destroyed() {
    this.observer.disconnect()
  },

  scrollToBottom() {
    this.el.scrollTop = this.el.scrollHeight
  },
}
