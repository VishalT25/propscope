import { Controller } from "@hotwired/stimulus"

// Removes a toast after a few seconds (it fades out first).
export default class extends Controller {
  connect() {
    this.fade = setTimeout(() => this.element.classList.add("toast-out"), 2200)
    this.gone = setTimeout(() => this.element.remove(), 2600)
  }

  disconnect() { clearTimeout(this.fade); clearTimeout(this.gone) }
}
