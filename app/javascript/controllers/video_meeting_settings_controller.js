import { Controller } from "@hotwired/stimulus"

// Simple controller to toggle video meeting provider section visibility
export default class extends Controller {
  static targets = ["providerSection"]

  toggleProvider(event) {
    const checkbox = event.target
    const providerSection = this.providerSectionTarget

    if (checkbox.checked) {
      providerSection.classList.remove("hidden")
    } else {
      providerSection.classList.add("hidden")
    }
  }
}
