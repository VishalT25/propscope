import { Controller } from "@hotwired/stimulus"

// A bottom sheet on mobile / side panel on desktop. Optional tabs (data-sheet-target="tab"/"pane")
// and kind filtering (data-kind) for the book selector.
export default class extends Controller {
  static targets = ["panel", "backdrop", "tab", "pane", "item"]

  connect() { this.onKey = (e) => { if (e.key === "Escape") this.close() }; document.addEventListener("keydown", this.onKey) }
  disconnect() { document.removeEventListener("keydown", this.onKey); document.body.classList.remove("overflow-hidden") }

  open(event) {
    const tab = event?.params?.tab
    this.panelTarget.hidden = false
    this.backdropTarget.hidden = false
    document.body.classList.add("overflow-hidden")
    if (tab) this.#showTab(tab)
  }

  close() {
    this.panelTarget.hidden = true
    this.backdropTarget.hidden = true
    document.body.classList.remove("overflow-hidden")
  }

  tab(event) { this.#showTab(event.params.name) }

  filterKind(event) {
    const kind = event.params.kind
    this.itemTargets.forEach((el) => { el.hidden = kind !== "any" && el.dataset.kind !== kind })
    this.tabTargets.forEach((t) => t.classList.toggle("chip-active", t.dataset.sheetKindParam === kind))
  }

  #showTab(name) {
    this.paneTargets.forEach((p) => { p.hidden = p.dataset.pane !== name })
    this.tabTargets.forEach((t) => t.classList.toggle("chip-active", t.dataset.sheetNameParam === name))
  }
}
