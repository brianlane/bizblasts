import { Controller } from "@hotwired/stimulus"

// Generic modal controller
export default class extends Controller {
  connect() {
    // Close modal on escape key
    this.boundHandleEscape = this.handleEscape.bind(this)
    document.addEventListener("keydown", this.boundHandleEscape)
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundHandleEscape)
  }

  open() {
    this.element.classList.remove("hidden")
    document.body.style.overflow = "hidden"
  }

  close() {
    this.element.classList.add("hidden")
    document.body.style.overflow = ""
  }

  handleEscape(event) {
    if (event.key === "Escape" && !this.element.classList.contains("hidden")) {
      this.close()
    }
  }

  closeOnBackdrop(event) {
    if (event.target === this.element) {
      this.close()
    }
  }
}
