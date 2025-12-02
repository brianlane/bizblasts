// app/javascript/controllers/rental_durations_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["container", "field", "input", "addButton"]
  static values = {
    maxOptions: { type: Number, default: 12 }
  }

  connect() {
    this.updateAddButtonState()
  }

  add(event) {
    event.preventDefault()

    // Check if we've reached the maximum
    if (this.fieldTargets.length >= this.maxOptionsValue) {
      alert(`Maximum ${this.maxOptionsValue} duration options allowed`)
      return
    }

    // Create new field
    const newField = document.createElement('div')
    newField.className = 'flex gap-2'
    newField.setAttribute('data-rental-durations-target', 'field')

    newField.innerHTML = `
      <div class="flex-1">
        <label class="block text-sm font-medium text-gray-700">Duration (minutes)</label>
        <input type="number"
               name="product[rental_duration_options][]"
               value=""
               min="15"
               step="15"
               class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500"
               placeholder="e.g., 60"
               data-rental-durations-target="input" />
      </div>
      <div class="flex items-end">
        <button type="button"
                class="px-3 py-2 text-red-600 hover:text-red-800 hover:bg-red-50 rounded-md transition-colors"
                data-action="click->rental-durations#remove"
                title="Remove duration">
          <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"/>
          </svg>
        </button>
      </div>
    `

    this.containerTarget.appendChild(newField)

    // Focus on the new input
    const newInput = newField.querySelector('input')
    if (newInput) {
      newInput.focus()
    }

    this.updateAddButtonState()
  }

  remove(event) {
    event.preventDefault()

    const field = event.target.closest('[data-rental-durations-target="field"]')
    if (!field) return

    // Don't allow removing if it's the last field
    if (this.fieldTargets.length <= 1) {
      alert('At least one duration option is required')
      return
    }

    // Immediately mark field as being removed to prevent race conditions
    field.dataset.removing = 'true'

    // Remove the field with animation
    field.style.opacity = '0'
    field.style.transform = 'scale(0.95)'
    field.style.transition = 'all 0.2s ease-out'

    setTimeout(() => {
      // Double-check we still have multiple fields before actual removal
      const remainingFields = this.fieldTargets.filter(f => !f.dataset.removing || f === field)
      if (remainingFields.length <= 1) {
        // Revert the animation if this would leave us with no fields
        field.style.opacity = '1'
        field.style.transform = 'scale(1)'
        delete field.dataset.removing
        alert('At least one duration option is required')
        return
      }

      field.remove()
      this.updateAddButtonState()
    }, 200)
  }

  updateAddButtonState() {
    if (!this.hasAddButtonTarget) return

    const currentCount = this.fieldTargets.length

    if (currentCount >= this.maxOptionsValue) {
      this.addButtonTarget.disabled = true
      this.addButtonTarget.classList.add('opacity-50', 'cursor-not-allowed')
      this.addButtonTarget.classList.remove('hover:bg-blue-100')
    } else {
      this.addButtonTarget.disabled = false
      this.addButtonTarget.classList.remove('opacity-50', 'cursor-not-allowed')
      this.addButtonTarget.classList.add('hover:bg-blue-100')
    }
  }
}
