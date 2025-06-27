import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["serviceTypeHidden", "serviceTypeError", "serviceTypeDropdown", "experienceFields", "form", "subscriptionSettings"]
  
  connect() {
    console.log("Service form controller connected")
    
    // Listen for service type changes
    if (this.hasServiceTypeHiddenTarget) {
      this.serviceTypeHiddenTarget.addEventListener('change', this.handleServiceTypeChange.bind(this))
    }
    
    // Listen for subscription checkbox changes
    this.setupSubscriptionToggle()
  }
  
  setupSubscriptionToggle() {
    const subscriptionCheckbox = document.getElementById('service_subscription_enabled')
    if (subscriptionCheckbox) {
      subscriptionCheckbox.addEventListener('change', this.handleSubscriptionChange.bind(this))
      
      // Initialize the subscription settings visibility on page load
      this.handleSubscriptionChange({ target: subscriptionCheckbox })
    }
  }
  
  handleSubscriptionChange(event) {
    const checkbox = event.target
    const subscriptionSettings = document.getElementById('service-subscription-settings')
    
    if (subscriptionSettings) {
      if (checkbox.checked) {
        subscriptionSettings.style.display = ''
        console.log("Subscription settings shown")
      } else {
        subscriptionSettings.style.display = 'none'
        console.log("Subscription settings hidden")
      }
    }
  }
  
  handleServiceTypeChange(event) {
    const value = event.target.value
    console.log("Service type changed to:", value)
    
    // Show/hide experience fields
    if (this.hasExperienceFieldsTarget) {
      if (value === 'experience') {
        this.experienceFieldsTarget.classList.remove('hidden')
      } else {
        this.experienceFieldsTarget.classList.add('hidden')
      }
    }
    
    // Clear validation error when a value is selected
    if (value && value !== '') {
      this.clearServiceTypeError()
    }
  }
  
  validateForm(event) {
    console.log("Form validation triggered")
    
    if (!this.hasServiceTypeHiddenTarget) {
      console.log("No service type hidden field found")
      return true
    }
    
    const serviceTypeValue = this.serviceTypeHiddenTarget.value
    console.log("Service type value:", serviceTypeValue)
    
    if (!serviceTypeValue || serviceTypeValue === '') {
      console.log("Service type validation failed - preventing form submission")
      event.preventDefault()
      event.stopPropagation()
      this.showServiceTypeError()
      this.scrollToServiceType()
      return false
    }
    
    console.log("Service type validation passed")
    this.clearServiceTypeError()
    return true
  }
  
  showServiceTypeError() {
    if (this.hasServiceTypeErrorTarget) {
      this.serviceTypeErrorTarget.classList.remove('hidden')
    }
    
    if (this.hasServiceTypeDropdownTarget) {
      const dropdownButton = this.serviceTypeDropdownTarget.querySelector('[data-dropdown-target="button"]')
      if (dropdownButton) {
        dropdownButton.classList.add('border-red-500', 'ring-red-500')
        dropdownButton.classList.remove('border-gray-300')
      }
    }
  }
  
  clearServiceTypeError() {
    if (this.hasServiceTypeErrorTarget) {
      this.serviceTypeErrorTarget.classList.add('hidden')
    }
    
    if (this.hasServiceTypeDropdownTarget) {
      const dropdownButton = this.serviceTypeDropdownTarget.querySelector('[data-dropdown-target="button"]')
      if (dropdownButton) {
        dropdownButton.classList.remove('border-red-500', 'ring-red-500')
        dropdownButton.classList.add('border-gray-300')
      }
    }
  }
  
  scrollToServiceType() {
    if (this.hasServiceTypeDropdownTarget) {
      this.serviceTypeDropdownTarget.scrollIntoView({ 
        behavior: 'smooth', 
        block: 'center' 
      })
    }
  }
} 