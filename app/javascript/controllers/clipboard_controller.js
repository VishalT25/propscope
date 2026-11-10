import { Controller } from "@hotwired/stimulus"

// Copies the text of the slip so it can be shared.
export default class extends Controller {
  static values = { text: String }
  static targets = ["label"]

  async copy() {
    try { await navigator.clipboard.writeText(this.textValue); this.#flash("Copied") } catch (e) { this.#flash("Press Ctrl/Cmd+C to copy") }
  }

  #flash(message) {
    const original = this.labelTarget.textContent
    this.labelTarget.textContent = message
    setTimeout(() => { this.labelTarget.textContent = original }, 1500)
  }
}
