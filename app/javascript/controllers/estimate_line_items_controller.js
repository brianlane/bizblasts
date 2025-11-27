import { Controller } from "@hotwired/stimulus"

// Enhanced line items controller for estimates with:
// - Multiple item types (service, product, labor, part)
// - Optional items support
// - "Save for Future Use" functionality (labor→service, part→product)
// - Dynamic total calculations
export default class extends Controller {
  static targets = [
    "items", "template", "item", "itemType", "serviceSelect",
    "productSelect", "laborFields", "miscFields", "subtotal",
    "taxes", "total", "optionalSubtotal", "optionalTaxes",
    "saveAsNewCheckbox", "saveAsNewFields", "newServiceName",
    "newServiceCategory", "itemTotal"
  ]

  static values = {
    estimateId: Number
  }

  connect() {
    console.log("EstimateLineItems controller connected")
    this.updateTotals()
  }

  addItem(event) {
    event.preventDefault()
    const content = this.templateTarget.innerHTML.replace(/NEW_RECORD/g, new Date().getTime())
    this.itemsTarget.insertAdjacentHTML('beforeend', content)
    this.updateTotals()
  }

  removeItem(event) {
    event.preventDefault()
    const item = event.currentTarget.closest('[data-estimate-line-items-target="item"]')

    const destroyField = item.querySelector("input[name*='_destroy']")
    if (destroyField) {
      destroyField.value = '1'
      item.style.display = 'none'
    } else {
      item.remove()
    }

    this.updateTotals()
  }

  changeItemType(event) {
    const item = event.target.closest('[data-estimate-line-items-target="item"]')
    const itemType = event.target.value

    // Show/hide relevant fields based on type
    const serviceSelect = item.querySelector('[data-field-type="service"]')
    const productSelect = item.querySelector('[data-field-type="product"]')
    const laborFields = item.querySelector('[data-field-type="labor"]')
    const standardFields = item.querySelector('[data-field-type="standard"]')
    const saveForFutureSection = item.querySelector('[data-field-type="save-for-future"]')

    // Hide all type-specific fields first
    if (serviceSelect) serviceSelect.classList.add('hidden')
    if (productSelect) productSelect.classList.add('hidden')
    if (laborFields) laborFields.classList.add('hidden')
    if (saveForFutureSection) saveForFutureSection.classList.add('hidden')

    // Hide both save-type sections within save-for-future
    const saveServiceSection = item.querySelector('[data-save-type="service"]')
    const saveProductSection = item.querySelector('[data-save-type="product"]')
    if (saveServiceSection) saveServiceSection.classList.add('hidden')
    if (saveProductSection) saveProductSection.classList.add('hidden')

    // Show relevant fields based on type
    switch (itemType) {
      case 'service':
        if (serviceSelect) serviceSelect.classList.remove('hidden')
        if (standardFields) standardFields.classList.remove('hidden')
        break
      case 'product':
        if (productSelect) productSelect.classList.remove('hidden')
        if (standardFields) standardFields.classList.remove('hidden')
        break
      case 'labor':
        if (laborFields) laborFields.classList.remove('hidden')
        if (standardFields) standardFields.classList.add('hidden')
        // Show save-for-future section with service save option
        if (saveForFutureSection) saveForFutureSection.classList.remove('hidden')
        if (saveServiceSection) saveServiceSection.classList.remove('hidden')
        break
      case 'part':
        if (standardFields) standardFields.classList.remove('hidden')
        // Show save-for-future section with product save option
        if (saveForFutureSection) saveForFutureSection.classList.remove('hidden')
        if (saveProductSection) saveProductSection.classList.remove('hidden')
        break
    }

    this.updateTotals()
  }

  selectService(event) {
    const item = event.target.closest('[data-estimate-line-items-target="item"]')
    const serviceId = event.target.value
    const selectedOption = event.target.options[event.target.selectedIndex]

    if (!serviceId || !selectedOption) return

    // Get service data from data attributes
    const price = selectedOption.dataset.price
    const description = selectedOption.dataset.description

    // Populate fields
    const descriptionField = item.querySelector('[name*="[description]"]')
    const costRateField = item.querySelector('[name*="[cost_rate]"]')
    const qtyField = item.querySelector('[name*="[qty]"]')

    if (descriptionField && description) descriptionField.value = description
    if (costRateField && price) costRateField.value = price
    if (qtyField && !qtyField.value) qtyField.value = 1

    this.calculateItemTotal(item)
  }

  selectProduct(event) {
    const item = event.target.closest('[data-estimate-line-items-target="item"]')
    const productId = event.target.value
    const selectedOption = event.target.options[event.target.selectedIndex]

    if (!productId || !selectedOption) return

    // Get product data from data attributes
    const price = selectedOption.dataset.price
    const description = selectedOption.dataset.description

    // Populate fields
    const descriptionField = item.querySelector('[name*="[description]"]')
    const costRateField = item.querySelector('[name*="[cost_rate]"]')
    const qtyField = item.querySelector('[name*="[qty]"]')

    if (descriptionField && description) descriptionField.value = description
    if (costRateField && price) costRateField.value = price
    if (qtyField && !qtyField.value) qtyField.value = 1

    this.calculateItemTotal(item)
  }

  calculateLaborTotal(event) {
    const item = event.target.closest('[data-estimate-line-items-target="item"]')
    const hoursField = item.querySelector('[name*="[hours]"]')
    const hourlyRateField = item.querySelector('[name*="[hourly_rate]"]')
    const costRateField = item.querySelector('[name*="[cost_rate]"]')
    const qtyField = item.querySelector('[name*="[qty]"]')

    const hours = parseFloat(hoursField?.value) || 0
    const hourlyRate = parseFloat(hourlyRateField?.value) || 0

    // For labor items, set cost_rate to hourly_rate and qty to ceil(hours)
    if (costRateField) costRateField.value = hourlyRate.toFixed(2)
    if (qtyField) qtyField.value = Math.ceil(hours) || 1

    this.calculateItemTotal(item)
  }

  calculateItemTotal(item) {
    const itemTypeField = item.querySelector('[name*="[item_type]"]')
    const itemType = itemTypeField?.value || 'service'

    let subtotal = 0

    if (itemType === 'labor') {
      const hoursField = item.querySelector('[name*="[hours]"]')
      const hourlyRateField = item.querySelector('[name*="[hourly_rate]"]')
      const hours = parseFloat(hoursField?.value) || 0
      const hourlyRate = parseFloat(hourlyRateField?.value) || 0
      subtotal = hours * hourlyRate
    } else {
      const qtyField = item.querySelector('[name*="[qty]"]')
      const costRateField = item.querySelector('[name*="[cost_rate]"]')
      const qty = parseFloat(qtyField?.value) || 0
      const costRate = parseFloat(costRateField?.value) || 0
      subtotal = qty * costRate
    }

    const taxRateField = item.querySelector('[name*="[tax_rate]"]')
    const taxRate = parseFloat(taxRateField?.value) || 0
    const tax = subtotal * (taxRate / 100)
    const total = subtotal + tax

    // Update item total display
    const totalDisplay = item.querySelector('[data-estimate-line-items-target="itemTotal"]')
    if (totalDisplay) {
      totalDisplay.textContent = `$${total.toFixed(2)}`
    }

    this.updateTotals()
  }

  inputChanged(event) {
    const item = event.target.closest('[data-estimate-line-items-target="item"]')
    if (item) {
      this.calculateItemTotal(item)
    }
  }

  updateTotals() {
    let requiredSubtotal = 0
    let requiredTaxes = 0
    let optionalSubtotal = 0
    let optionalTaxes = 0

    this.itemTargets.forEach(item => {
      if (item.style.display === 'none') return // Skip removed items

      const destroyField = item.querySelector("input[name*='_destroy']")
      if (destroyField && destroyField.value === '1') return // Skip destroyed items

      const itemTypeField = item.querySelector('[name*="[item_type]"]')
      const itemType = itemTypeField?.value || 'service'

      let itemSubtotal = 0

      if (itemType === 'labor') {
        const hoursField = item.querySelector('[name*="[hours]"]')
        const hourlyRateField = item.querySelector('[name*="[hourly_rate]"]')
        const hours = parseFloat(hoursField?.value) || 0
        const hourlyRate = parseFloat(hourlyRateField?.value) || 0
        itemSubtotal = hours * hourlyRate
      } else {
        const qtyField = item.querySelector('[name*="[qty]"]')
        const costRateField = item.querySelector('[name*="[cost_rate]"]')
        const qty = parseFloat(qtyField?.value) || 0
        const costRate = parseFloat(costRateField?.value) || 0
        itemSubtotal = qty * costRate
      }

      const taxRateField = item.querySelector('[name*="[tax_rate]"]')
      const optionalCheckbox = item.querySelector('[name*="[optional]"]')

      const taxRate = parseFloat(taxRateField?.value) || 0
      const isOptional = optionalCheckbox?.checked || false

      const tax = itemSubtotal * (taxRate / 100)

      if (isOptional) {
        optionalSubtotal += itemSubtotal
        optionalTaxes += tax
      } else {
        requiredSubtotal += itemSubtotal
        requiredTaxes += tax
      }
    })

    const requiredTotal = requiredSubtotal + requiredTaxes
    const optionalTotal = optionalSubtotal + optionalTaxes
    const grandTotal = requiredTotal + optionalTotal

    // Update display elements
    if (this.hasSubtotalTarget) {
      this.subtotalTarget.textContent = `$${requiredSubtotal.toFixed(2)}`
    }
    if (this.hasTaxesTarget) {
      this.taxesTarget.textContent = `$${requiredTaxes.toFixed(2)}`
    }
    if (this.hasTotalTarget) {
      this.totalTarget.textContent = `$${grandTotal.toFixed(2)}`
    }
    if (this.hasOptionalSubtotalTarget) {
      this.optionalSubtotalTarget.textContent = `$${optionalSubtotal.toFixed(2)}`
    }
    if (this.hasOptionalTaxesTarget) {
      this.optionalTaxesTarget.textContent = `$${optionalTaxes.toFixed(2)}`
    }
  }

  // "Save for Future Use" functionality - toggle fields visibility
  toggleSaveForFuture(event) {
    const checkbox = event.target
    const container = checkbox.closest('[data-field-type="save-for-future"]')
    const fieldsToToggle = container?.querySelector('[data-field-type="save-service-fields"]') ||
                           container?.querySelector('[data-field-type="save-product-fields"]')

    if (!fieldsToToggle) return

    if (checkbox.checked) {
      fieldsToToggle.classList.remove('hidden')
      // Auto-populate name from description if available
      const item = checkbox.closest('tr[data-estimate-line-items-target="item"]') ||
                   checkbox.closest('template')?.content?.querySelector('tr[data-estimate-line-items-target="item"]')
      if (item) {
        const descriptionField = item.querySelector('[name*="[description]"]')
        const nameField = fieldsToToggle.querySelector('[name*="[service_name]"], [name*="[product_name]"]')
        if (descriptionField && nameField && !nameField.value) {
          nameField.value = descriptionField.value
        }
      }
    } else {
      fieldsToToggle.classList.add('hidden')
    }
  }
}

