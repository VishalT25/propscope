import { Controller } from "@hotwired/stimulus"

// Reloads a Turbo Frame every few seconds. Put it on an element INSIDE the frame: when the server stops rendering that element
// (the work finished), the controller disconnects and the polling stops by itself.
export default class extends Controller {
  static values = { frame: String, interval: { type: Number, default: 3000 } }

  connect() {
    this.timer = setInterval(() => document.getElementById(this.frameValue)?.reload(), this.intervalValue)
  }

  disconnect() { clearInterval(this.timer) }
}
