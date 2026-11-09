import { Controller } from "@hotwired/stimulus"

// Dark (default) / light. Stored per-viewer in localStorage only.
export default class extends Controller {
  static targets = ["dark", "light"]

  connect() { this.#paint() }
  dark() { this.#set("dark") }
  light() { this.#set("light") }

  #set(theme) {
    document.documentElement.dataset.theme = theme
    try { localStorage.setItem("theme", theme) } catch (e) { /* storage unavailable */ }
    this.#paint()
  }

  #paint() {
    const current = document.documentElement.dataset.theme
    for (const [name, el] of [["dark", this.darkTarget], ["light", this.lightTarget]]) {
      el.classList.toggle("bg-accent", name === current)
      el.classList.toggle("text-white", name === current)
      el.classList.toggle("text-muted", name !== current)
      el.setAttribute("aria-pressed", name === current)
    }
  }
}
