import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "menu", "option", "hidden", "newCustomerFields"]
  static values = { 
    selectedValue: String,
    selectedText: String 
  }
  
  connect() {
    this.isOpen = false
    this.setInitialState()
    this.setupOutsideClickListener()
  }
  
  disconnect() {
    this.removeOutsideClickListener()
  }
  
  setInitialState() {
    // Set initial selected state if we have a selected value
    if (this.selectedValueValue) {
      const selectedOption = this.optionTargets.find(option => 
        (option.dataset.itemId || option.dataset.customerId) === this.selectedValueValue
      )
      if (selectedOption) {
        this.selectOption(selectedOption, false)
      }
    }
    
    // Set initial new customer fields visibility
    this.toggleNewCustomerFields(this.selectedValueValue === 'new')
  }
  
  toggle(event) {
    event.preventDefault()
    event.stopPropagation()
    
    this.isOpen ? this.close() : this.open()
  }
  
  open() {
    this.menuTarget.classList.remove('hidden')
    this.buttonTarget.setAttribute('aria-expanded', 'true')
    
    // Rotate arrow if present
    const arrow = this.buttonTarget.querySelector('svg')
    if (arrow) arrow.classList.add('rotate-180')
    
    this.isOpen = true
  }
  
  close() {
    this.menuTarget.classList.add('hidden')
    this.buttonTarget.setAttribute('aria-expanded', 'false')
    
    // Reset arrow rotation
    const arrow = this.buttonTarget.querySelector('svg')
    if (arrow) arrow.classList.remove('rotate-180')
    
    this.isOpen = false
  }
  
  selectOption(optionElement, shouldClose = true) {
    // Support both data-item-* and data-customer-* attribute conventions
    const itemId   = optionElement.dataset.itemId   || optionElement.dataset.customerId
    const itemText = optionElement.dataset.itemText || optionElement.dataset.customerName || optionElement.textContent.trim()
    
    // Locate the hidden field even if it exists outside the controller element
    const hiddenField = this.hasHiddenTarget ? this.hiddenTarget : this.element.closest('form')?.querySelector('[data-customer-dropdown-target="hidden"]')
    if (hiddenField) {
      hiddenField.value = itemId
    }
    
    // Update button text
    const textElement = this.buttonTarget.querySelector('.customer-dropdown-text')
    if (textElement) {
      textElement.textContent = itemText
    }
    
    // Update visual selection state
    this.clearSelectedStates()
    this.markAsSelected(optionElement)
    
    // Store selected values
    this.selectedValueValue = itemId
    this.selectedTextValue = itemText
    
    // Toggle new customer fields based on selection
    this.toggleNewCustomerFields(itemId === 'new')
    
    if (shouldClose) {
      this.close()
    }
    
    // Trigger change event for form validation
    if (hiddenField) {
      hiddenField.dispatchEvent(new Event('change', { bubbles: true }))
    }
    
    // Trigger custom event for other listeners
    this.dispatch('selected', { 
      detail: { 
        value: itemId, 
        text: itemText,
        element: optionElement 
      } 
    })
  }

  
  toggleNewCustomerFields(show) {
    const container = this.hasNewCustomerFieldsTarget
      ? this.newCustomerFieldsTarget
      : this.element.closest('form')?.querySelector('[data-customer-dropdown-target="newCustomerFields"]')

    if (!container) return

    const fields = container.querySelectorAll('input[name*="[first_name]"], input[name*="[last_name]"], input[name*="[email]"], input[name*="[phone]"]')

    if (show) {
      container.classList.remove('hidden')
      container.style.display = ''
      fields.forEach(field => {
        field.required = true
        field.disabled = false
      })
    } else {
      container.classList.add('hidden')
      container.style.display = 'none'
      fields.forEach(field => {
        field.required = false
        field.disabled = false
      })
    }
  }

  
  clearSelectedStates() {
    this.optionTargets.forEach(option => {
      const checkIcon = option.querySelector('.absolute.inset-y-0.right-2')
      if (checkIcon) checkIcon.remove()
    })
  }
  
  markAsSelected(optionElement) {
    const checkIcon = document.createElement('span')
    checkIcon.className = 'absolute inset-y-0 right-2 flex items-center text-blue-600'
    checkIcon.innerHTML = `
      <svg class="h-5 w-5" fill="currentColor" viewBox="0 0 20 20">
        <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd"/>
      </svg>
    `
    optionElement.appendChild(checkIcon)
  }
  
  // Action methods called from templates
  select(event) {
    event.preventDefault()
    event.stopPropagation()
    this.selectOption(event.currentTarget)
  }
  
  closeOnEscape(event) {
    if (event.key === 'Escape' && this.isOpen) {
      this.close()
    }
  }
  
  setupOutsideClickListener() {
    this.outsideClickHandler = (event) => {
      if (this.isOpen && !this.element.contains(event.target)) {
        this.close()
      }
    }
    
    document.addEventListener('click', this.outsideClickHandler)
    document.addEventListener('touchend', this.outsideClickHandler)
    document.addEventListener('keydown', this.closeOnEscape.bind(this))
  }
  
  removeOutsideClickListener() {
    if (this.outsideClickHandler) {
      document.removeEventListener('click', this.outsideClickHandler)
      document.removeEventListener('touchend', this.outsideClickHandler)
      document.removeEventListener('keydown', this.closeOnEscape.bind(this))
    }
  }
} 