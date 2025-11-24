import { Controller } from "@hotwired/stimulus"

// Toggles the enhanced accent color dropdown based on layout selection.
export default class extends Controller {
  static targets = ["accentWrapper", "layoutInput"]

  connect() {
    this.toggle()
  }

  toggle() {
    if (!this.hasAccentWrapperTarget) return
    const enhancedSelected = this.layoutInputTargets.some((input) => input.value === "enhanced" && input.checked)
    this.accentWrapperTarget.classList.toggle("hidden", !enhancedSelected)
  }
}

