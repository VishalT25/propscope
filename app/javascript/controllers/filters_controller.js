import { Controller } from "@hotwired/stimulus"

// The props filters. One form (#filters_form) holds every filter; the toolbar and the side panel are just two places to change it.
//   * every change applies straight away (debounced) into the results frame, and the URL follows, so views stay shareable
//   * the toolbar keeps itself honest without a page load: chips light up when their filter has something chosen, the Filters
//     badge counts them, and the prop count follows the results
//   * the saved-filter form saves what is on screen now, not what the page was loaded with
export default class extends Controller {
  static targets = ["group", "chip", "badge", "clear", "count", "applyLabel"]
  static values = { form: { type: String, default: "filters_form" } }

  connect() {
    this.onFrameLoad = (event) => { if (event.target.id === "props_results") this.#showTotals(event.target) }
    document.addEventListener("turbo:frame-load", this.onFrameLoad)
    this.#sync()
  }

  disconnect() {
    clearTimeout(this.timer)
    document.removeEventListener("turbo:frame-load", this.onFrameLoad)
  }

  // Keep shared URLs short: drop empty fields from the submitted form data.
  strip(event) {
    for (const [key, value] of [...event.formData]) { if (value === "") event.formData.delete(key) }
    if (!event.formData.has("min_hit_rate")) event.formData.delete("hit_window") // the window means nothing without a minimum
  }

  // Any input that belongs to the filters form (by DOM position or the form= attribute).
  changed(event) {
    if (event.target.form?.id !== this.formValue) return

    this.#sync()
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.form.requestSubmit(), event.type === "input" ? 400 : 120)
  }

  // On the saved-filter form: replace the filters it was rendered with by the ones currently chosen.
  fillSaved(event) {
    const keep = ["name", "authenticity_token", "commit", "utf8"]
    for (const key of [...new Set([...event.formData.keys()])]) { if (!keep.includes(key)) event.formData.delete(key) }
    for (const [key, value] of new FormData(this.form)) {
      if (value !== "" && !["sort", "dir", "authenticity_token"].includes(key)) event.formData.append(key, value)
    }
  }

  get form() { return document.getElementById(this.formValue) }

  #sync() {
    const active = new Set()
    this.groupTargets.forEach((group) => { if (this.#isActive(group)) active.add(group.dataset.group) })
    this.chipTargets.forEach((chip) => {
      chip.dataset.active = active.has(chip.dataset.group) ? "true" : "false"
      const counter = chip.querySelector("[data-chip-count]")
      if (counter) {
        const group = this.groupTargets.find((g) => g.dataset.group === chip.dataset.group)
        const chosen = group ? group.querySelectorAll("input[type=checkbox]:checked").length : 0
        counter.textContent = chosen > 0 ? chosen : ""
        counter.hidden = chosen === 0
      }
    })
    this.badgeTargets.forEach((badge) => { badge.textContent = active.size; badge.hidden = active.size === 0 })
    this.clearTargets.forEach((el) => { el.hidden = active.size === 0 })
  }

  #isActive(group) {
    return [...group.querySelectorAll("input, select")].some((el) => {
      if (el.dataset.ignore !== undefined || el.type === "hidden" || el.disabled) return false // e.g. the hit-rate window means nothing alone
      if (el.type === "checkbox" || el.type === "radio") return el.checked && el.value !== ""
      return el.value.trim() !== ""
    })
  }

  // The results frame carries the new totals; the toolbar (outside the frame) shows them.
  #showTotals(frame) {
    const totals = frame.querySelector("[data-total]")
    if (!totals) return
    this.countTargets.forEach((el) => { el.textContent = totals.dataset.countLabel })
    this.applyLabelTargets.forEach((el) => { el.textContent = totals.dataset.applyLabel })
  }
}
