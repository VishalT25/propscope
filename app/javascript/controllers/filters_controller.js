import { Controller } from "@hotwired/stimulus"

// Live result count: on any change, ask the server how many props match and swap the button label
// via a Turbo Stream (debounced).
export default class extends Controller {
  static values = { countUrl: String }

  disconnect() { clearTimeout(this.timer) }

  // Keep shared URLs short: drop empty fields from the submitted form data.
  strip(event) {
    for (const [key, value] of [...event.formData]) { if (value === "") event.formData.delete(key) }
  }

  changed() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.#refresh(), 250)
  }

  async #refresh() {
    const params = new URLSearchParams()
    for (const [key, value] of new FormData(this.element)) {
      if (value !== "" && !["authenticity_token", "name", "commit"].includes(key)) params.append(key, value)
    }
    const response = await fetch(`${this.countUrlValue}?${params}`, { headers: { Accept: "text/vnd.turbo-stream.html" } })
    if (response.ok) window.Turbo.renderStreamMessage(await response.text())
  }
}
