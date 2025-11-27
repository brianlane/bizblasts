import { Controller } from "@hotwired/stimulus"

// Enhanced line items controller for estimates with:
// - Multiple item types (service, product, labor, part, misc)
// - Optional items support
// - "Save as New Service" functionality for labor items
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
    const saveAsNewSection = item.querySelector('[data-field-type="save-as-new"]')

    // Hide all type-specific fields first
    if (serviceSelect) serviceSelect.classList.add('hidden')
    if (productSelect) productSelect.classList.add('hidden')
    if (laborFields) laborFields.classList.add('hidden')
    if (saveAsNewSection) saveAsNewSection.classList.add('hidden')

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
        if (saveAsNewSection) saveAsNewSection.classList.remove('hidden')
        if (standardFields) standardFields.classList.add('hidden')
        break
      case 'part':
      case 'misc':
        if (standardFields) standardFields.classList.remove('hidden')
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

  // "Save as New Service" functionality for labor items
  toggleSaveAsNew(event) {
    const checkbox = event.target
    const item = checkbox.closest('[data-estimate-line-items-target="item"]')
    const saveAsNewFields = item.querySelector('[data-field-type="save-as-new-details"]')

    if (saveAsNewFields) {
      if (checkbox.checked) {
        saveAsNewFields.classList.remove('hidden')
        // Populate service name from description if empty
        const descriptionField = item.querySelector('[name*="[description]"]')
        const serviceNameField = saveAsNewFields.querySelector('[data-estimate-line-items-target="newServiceName"]')
        if (serviceNameField && !serviceNameField.value && descriptionField) {
          serviceNameField.value = descriptionField.value
        }
      } else {
        saveAsNewFields.classList.add('hidden')
      }
    }
  }

  // Create a new service from labor item data via AJAX
  async createServiceFromLabor(event) {
    event.preventDefault()

    const button = event.currentTarget
    const item = button.closest('[data-estimate-line-items-target="item"]')

    // Get labor item data
    const descriptionField = item.querySelector('[name*="[description]"]')
    const hoursField = item.querySelector('[name*="[hours]"]')
    const hourlyRateField = item.querySelector('[name*="[hourly_rate]"]')
    const serviceNameField = item.querySelector('[data-estimate-line-items-target="newServiceName"]')
    const categoryField = item.querySelector('[data-estimate-line-items-target="newServiceCategory"]')

    // Validate required fields
    const serviceName = serviceNameField?.value?.trim()
    const hours = parseFloat(hoursField?.value) || 0
    const hourlyRate = parseFloat(hourlyRateField?.value) || 0
    const description = descriptionField?.value?.trim()

    if (!serviceName) {
      alert('Please enter a service name')
      serviceNameField?.focus()
      return
    }

    if (hours <= 0 || hourlyRate <= 0) {
      alert('Please enter valid hours and hourly rate')
      return
    }

    // Calculate service price and duration from labor
    const price = hours * hourlyRate
    const duration = Math.ceil(hours * 60) // Convert hours to minutes, round up

    // Prepare service data
    const serviceData = {
      service: {
        name: serviceName,
        description: description || `${serviceName} - created from estimate`,
        price: price.toFixed(2),
        duration: duration,
        active: true,
        tips_enabled: false,
        allow_discounts: true,
        created_from_estimate_id: this.estimateIdValue || null
      }
    }

    // Add category if provided (as description suffix)
    if (categoryField?.value?.trim()) {
      serviceData.service.description = `${categoryField.value.trim()}: ${serviceData.service.description}`
    }

    // Disable button during request
    button.disabled = true
    button.textContent = 'Creating...'

    try {
      // Get CSRF token
      const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

      // Make AJAX request to create service
      const response = await fetch('/manage/services', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'X-CSRF-Token': csrfToken
        },
        body: JSON.stringify(serviceData)
      })

      if (response.ok) {
        const data = await response.json()

        // Update the estimate item to use the new service
        this.convertLaborToService(item, data.service)

        // Show success message
        this.showNotification('Service created successfully!', 'success')
      } else {
        const errorData = await response.json()
        throw new Error(errorData.error || 'Failed to create service')
      }
    } catch (error) {
      console.error('Error creating service:', error)
      alert(`Failed to create service: ${error.message}`)

      // Re-enable button
      button.disabled = false
      button.textContent = 'Create Service'
    }
  }

  // Convert a labor item to a service item after service creation
  convertLaborToService(item, service) {
    // Update item type to service
    const itemTypeField = item.querySelector('[name*="[item_type]"]')
    if (itemTypeField) {
      itemTypeField.value = 'service'
    }

    // Set the service_id
    const serviceIdField = item.querySelector('[name*="[service_id]"]')
    if (serviceIdField) {
      // Create new option for the service select
      const serviceSelect = item.querySelector('[data-field-type="service"] select')
      if (serviceSelect) {
        const option = document.createElement('option')
        option.value = service.id
        option.text = service.name
        option.setAttribute('data-price', service.price)
        option.setAttribute('data-description', service.description)
        option.selected = true
        serviceSelect.appendChild(option)
      }
    }

    // Hide labor fields, show service select
    const laborFields = item.querySelector('[data-field-type="labor"]')
    const serviceFields = item.querySelector('[data-field-type="service"]')
    const standardFields = item.querySelector('[data-field-type="standard"]')
    const saveAsNewSection = item.querySelector('[data-field-type="save-as-new"]')

    if (laborFields) laborFields.classList.add('hidden')
    if (serviceFields) serviceFields.classList.remove('hidden')
    if (standardFields) standardFields.classList.remove('hidden')
    if (saveAsNewSection) saveAsNewSection.classList.add('hidden')

    // Update qty and cost_rate from the service
    const qtyField = item.querySelector('[name*="[qty]"]')
    const costRateField = item.querySelector('[name*="[cost_rate]"]')

    if (qtyField) qtyField.value = 1
    if (costRateField) costRateField.value = service.price

    // Recalculate totals
    this.calculateItemTotal(item)
  }

  // Show notification message
  showNotification(message, type = 'info') {
    // Create notification element
    const notification = document.createElement('div')
    notification.className = `fixed top-4 right-4 px-6 py-3 rounded-lg shadow-lg z-50 ${
      type === 'success' ? 'bg-green-500 text-white' :
      type === 'error' ? 'bg-red-500 text-white' :
      'bg-blue-500 text-white'
    }`
    notification.textContent = message

    document.body.appendChild(notification)

    // Auto-remove after 3 seconds
    setTimeout(() => {
      notification.remove()
    }, 3000)
  }
}

