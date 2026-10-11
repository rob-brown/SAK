const AutoFocus = {
  mounted() {
    this.el.focus()
    if (typeof this.el.select === "function") this.el.select()
  },
}

export default AutoFocus
