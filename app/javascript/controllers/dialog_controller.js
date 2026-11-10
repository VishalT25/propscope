import { Controller } from "@hotwired/stimulus"

// Opens a native <dialog> by id (daisyUI .modal). Native dialogs sit in the top layer, so they are not clipped by the
// blurred sticky header, and Esc / backdrop click close them for free.
export default class extends Controller {
  open(event) { document.getElementById(event.params.id)?.showModal() }
}
