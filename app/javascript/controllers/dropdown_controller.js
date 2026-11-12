import { Controller } from "@hotwired/stimulus"

// A dropdown under its button, built on the native popover API: it opens in the browser's top layer, so a horizontally scrolling
// toolbar cannot clip it, and the browser handles click-outside and Escape. This only places it: under the button, kept on screen.
export default class extends Controller {
  static targets = ["button", "panel"]

  connect() {
    this.place = this.place.bind(this)
    this.panelTarget.addEventListener("toggle", this.place)
    window.addEventListener("resize", this.close = () => { if (this.panelTarget.matches(":popover-open")) this.panelTarget.hidePopover() })
  }

  disconnect() {
    this.panelTarget.removeEventListener("toggle", this.place)
    window.removeEventListener("resize", this.close)
  }

  place(event) {
    if (event.newState !== "open") return
    const button = this.buttonTarget.getBoundingClientRect()
    const panel = this.panelTarget
    const margin = 8
    panel.style.top = `${Math.round(button.bottom + 6)}px`
    panel.style.left = `${Math.round(Math.max(margin, Math.min(button.left, window.innerWidth - panel.offsetWidth - margin)))}px`
    const first = panel.querySelector("input:not([type=hidden]), button, select")
    if (first && first.type !== "checkbox" && first.type !== "radio") first.focus({ preventScroll: true })
  }
}
