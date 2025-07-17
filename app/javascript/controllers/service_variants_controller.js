import { Controller } from "@hotwired/stimulus"

// Controller handles dynamic add/remove of nested service_variant fields on the Service form.
// Inspired by product_variants_controller but simplified.
export default class extends Controller {
  static targets = ["container", "addButton", "baseFields"]

  connect() {
    this.counter = 0
    if (this.hasBaseFieldsTarget) {
      this.updateBaseFieldsVisibility()
    }
  }

  addVariant(event) {
    event.preventDefault()
    const timestamp = Date.now() + this.counter++
    const variantHTML = this.buildVariantHTML(timestamp)
    this.containerTarget.insertAdjacentHTML("beforeend", variantHTML)
    if (this.hasBaseFieldsTarget) {
      this.updateBaseFieldsVisibility()
    }
  }

  removeVariant(event) {
    event.preventDefault()
    const wrapper = event.target.closest('.variant-field')
    if (!wrapper) return

    const destroyInput = wrapper.querySelector('input[name*="[_destroy]"]')
    if (destroyInput) {
      destroyInput.value = '1'
      wrapper.style.display = 'none'
    } else {
      wrapper.remove()
    }

    if (this.hasBaseFieldsTarget) {
      this.updateBaseFieldsVisibility()
    }
  }

  updateBaseFieldsVisibility() {
    // Count visible variant fields that are not marked for destruction
    const activeVariants = Array.from(this.containerTarget.querySelectorAll('.variant-field')).filter(el => {
      const destroyInput = el.querySelector('input[name*="[_destroy]"]')
      return !(destroyInput && destroyInput.value === '1') && el.style.display !== 'none'
    })

    if (activeVariants.length > 0) {
      this.baseFieldsTarget.style.display = 'none'
    } else {
      this.baseFieldsTarget.style.display = ''
    }
  }

  buildVariantHTML(key) {
    return `
      <div class="variant-field bg-gray-50 border border-gray-200 rounded-lg p-4 mb-4">
        <div class="flex items-center justify-between mb-4">
          <h4 class="text-md font-medium text-gray-900">Service Variant</h4>
          <button type="button" class="remove-variant inline-flex items-center px-3 py-1 text-xs font-medium text-red-600 bg-red-50 hover:bg-red-100 rounded-md" data-action="click->service-variants#removeVariant">
            Remove Variant
          </button>
        </div>
        <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
          <div>
            <label class="block text-gray-700 text-sm font-bold mb-2">Name</label>
            <input type="text" name="service[service_variants_attributes][${key}][name]" class="w-full border rounded px-3 py-2" required />
          </div>
          <div>
            <label class="block text-gray-700 text-sm font-bold mb-2">Duration (min)</label>
            <input type="number" name="service[service_variants_attributes][${key}][duration]" class="w-full border rounded px-3 py-2" min="1" required />
          </div>
          <div>
            <label class="block text-gray-700 text-sm font-bold mb-2">Price</label>
            <input type="number" step="0.01" name="service[service_variants_attributes][${key}][price]" class="w-full border rounded px-3 py-2" required />
          </div>
          <div class="flex items-center col-span-1">
            <input type="checkbox" name="service[service_variants_attributes][${key}][active]" value="1" class="mr-2" checked /> Active
          </div>
        </div>
      </div>
    `
  }
} 