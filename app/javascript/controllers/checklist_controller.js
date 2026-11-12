import { Controller } from "@hotwired/stimulus"

// Select all / Deselect all for a list of checkboxes, with a "N of M selected" count and an optional submit button that stays
// disabled while the list is empty (the books list needs at least one). Items hidden by a filter (the book kind tabs) are left alone.
export default class extends Controller {
  static targets = ["box", "count", "submit"]
  static values = { noun: { type: String, default: "selected" }, minimum: { type: Number, default: 0 } }

  connect() { this.update() }

  all() { this.#setAll(true) }
  none() { this.#setAll(false) }

  update() {
    const boxes = this.boxTargets
    const chosen = boxes.filter((box) => box.checked).length
    if (this.hasCountTarget) this.countTarget.textContent = `${chosen} of ${boxes.length} ${this.nounValue}`
    if (this.hasSubmitTarget) {
      const short = chosen < this.minimumValue
      this.submitTarget.disabled = short
      this.submitTarget.title = short ? "Choose at least one" : ""
    }
  }

  #setAll(checked) {
    this.boxTargets.forEach((box) => {
      if (box.closest("[hidden]") || box.checked === checked) return
      box.checked = checked
      box.dispatchEvent(new Event("change", { bubbles: true })) // so a live form (the props filters) notices
    })
    this.update()
  }
}
