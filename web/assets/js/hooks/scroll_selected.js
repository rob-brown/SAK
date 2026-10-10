const ScrollSelected = {
  mounted() {
    this.scrollToSelected()
  },

  updated() {
    this.scrollToSelected()
  },

  scrollToSelected() {
    const selected = this.el.querySelector('[data-selected="true"]')
    if (selected) selected.scrollIntoView({block: "nearest"})
  },
}

export default ScrollSelected
