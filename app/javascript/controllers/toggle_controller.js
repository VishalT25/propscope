import { Controller } from "@hotwired/stimulus"

// Show/hide a panel. Closes on Esc, outside click, Turbo navigation, or when another toggle opens.
export default class extends Controller {
  static targets = ["panel", "button"]

  connect() {
    this.boundHide = () => this.hide()
    this.boundOther = (event) => { if (event.detail !== this.element) this.hide() }
    document.addEventListener("turbo:before-visit", this.boundHide)
    window.addEventListener("toggle:opened", this.boundOther)
  }

  disconnect() {
    document.removeEventListener("turbo:before-visit", this.boundHide)
    window.removeEventListener("toggle:opened", this.boundOther)
  }

  toggle() { this.panelTarget.hidden ? this.show() : this.hide() }

  show() {
    this.panelTarget.hidden = false
    this.#expanded(true)
    window.dispatchEvent(new CustomEvent("toggle:opened", { detail: this.element }))
  }

  hide() { if (this.hasPanelTarget) { this.panelTarget.hidden = true; this.#expanded(false) } }
  clickOutside(event) { if (!this.element.contains(event.target)) this.hide() }

  #expanded(value) { if (this.hasButtonTarget) this.buttonTarget.setAttribute("aria-expanded", value) }
}
