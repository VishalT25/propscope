import { Controller } from "@hotwired/stimulus"

// Many images at once. The files are sent in small batches (a request is limited to 128 files, and big requests are slow to retry),
// and every file ends up with a result: added, or skipped with the reason. Names come from the user's files, so they are only
// ever written with textContent.
const MAX_BYTES = 2 * 1024 * 1024

export default class extends Controller {
  static targets = ["input", "status", "results", "count"]
  static values = { url: String, league: String, kind: String, batch: { type: Number, default: 20 } }

  async upload() {
    const files = Array.from(this.inputTarget.files)
    if (files.length === 0) return

    this.inputTarget.disabled = true
    this.resultsTarget.replaceChildren()
    const results = []
    const sendable = []
    files.forEach((file) => {
      if (file.size > MAX_BYTES) results.push({ file: file.name, status: "skipped", message: "That file is over 2 MB." })
      else sendable.push(file)
    })

    for (let i = 0; i < sendable.length; i += this.batchValue) {
      const batch = sendable.slice(i, i + this.batchValue)
      this.statusTarget.textContent = `Uploading ${i + 1} to ${i + batch.length} of ${sendable.length}…`
      try {
        const data = await this.#send(batch)
        results.push(...data.results)
        this.#showCount(data.totals)
      } catch (error) {
        batch.forEach((file) => results.push({ file: file.name, status: "skipped", message: error.message }))
      }
    }

    this.#summarise(results)
    this.inputTarget.value = ""
    this.inputTarget.disabled = false
  }

  async #send(batch) {
    const body = new FormData()
    body.append("league", this.leagueValue)
    body.append("kind", this.kindValue)
    batch.forEach((file) => body.append("files[]", file))
    const token = document.querySelector("meta[name=csrf-token]")?.content
    const response = await fetch(this.urlValue, { method: "POST", body, credentials: "same-origin", headers: { "X-CSRF-Token": token, Accept: "application/json" } })
    if (!response.ok) {
      const detail = await response.json().catch(() => ({}))
      throw new Error(detail.error || `The upload failed (${response.status}). Try those files again.`)
    }
    return response.json()
  }

  #showCount(totals) {
    if (this.hasCountTarget && totals) this.countTarget.textContent = totals.with_image
  }

  #summarise(results) {
    const saved = results.filter((r) => r.status === "saved")
    const skipped = results.filter((r) => r.status !== "saved")
    this.statusTarget.textContent = `${saved.length} added, ${skipped.length} skipped.`

    if (skipped.length > 0) {
      const list = document.createElement("ul")
      list.className = "mt-2 divide-y divide-line rounded-xl border border-line text-sm"
      skipped.forEach((r) => {
        const item = document.createElement("li")
        item.className = "px-3 py-2"
        const name = document.createElement("b")
        name.textContent = r.file
        const why = document.createElement("span")
        why.className = "text-miss"
        why.textContent = ` ${r.message}`
        item.append(name, why)
        list.append(item)
      })
      this.resultsTarget.append(list)
    }

    if (saved.length > 0) {
      const details = document.createElement("details")
      details.className = "mt-2 text-sm"
      const summary = document.createElement("summary")
      summary.className = "cursor-pointer font-semibold text-hit"
      summary.textContent = `Show the ${saved.length} that were added`
      const list = document.createElement("ul")
      list.className = "mt-1 space-y-0.5 text-muted"
      saved.forEach((r) => {
        const item = document.createElement("li")
        item.textContent = `${r.file} → ${r.target}`
        list.append(item)
      })
      details.append(summary, list)
      this.resultsTarget.append(details)
      const note = document.createElement("p")
      note.className = "mt-2 text-xs text-muted"
      note.textContent = "Reload the page to see them in the lists below."
      this.resultsTarget.append(note)
    }
  }
}
