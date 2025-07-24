import { Controller } from "@hotwired/stimulus"

console.log("=== SERVICE FORM CONTROLLER MODULE LOADED ===")

export default class extends Controller {
  static targets = ["serviceTypeHidden", "serviceTypeError", "serviceTypeDropdown", "experienceFields", "form", "subscriptionSettings", "availabilityStatus"]
  
  connect() {
    console.log("=== SERVICE FORM CONTROLLER CONNECTED ===")
    console.log("Element:", this.element)
    console.log("Element tag:", this.element.tagName)
    console.log("Data controller attribute:", this.element.getAttribute('data-controller'))
    console.log("Data action attribute:", this.element.getAttribute('data-action'))
    
    // Check if we can find the Use Default button
    const useDefaultButton = this.element.querySelector('[data-action*="clearAvailability"]')
    console.log("Use Default button found:", useDefaultButton)
    
    // Test if the form submit handler is working
    this.element.addEventListener('submit', (e) => {
      console.log("=== FORM SUBMIT EVENT CAPTURED ===")
      console.log("About to call validateForm")
    })
    
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
    console.log("=== FORM VALIDATION STARTED ===")
    console.log("Event:", event)
    
    if (!this.hasServiceTypeHiddenTarget) {
      console.log("No service type hidden target - allowing submission")
      return true
    }
    
    const serviceTypeValue = this.serviceTypeHiddenTarget.value
    console.log("Service type value:", serviceTypeValue)
    
    // For existing services, service_type should already be set
    if (!serviceTypeValue || serviceTypeValue === '') {
      console.log("=== BLOCKING SUBMISSION - EMPTY SERVICE TYPE ===")
      event.preventDefault()
      event.stopPropagation()
      this.showServiceTypeError()
      this.scrollToServiceType()
      return false
    }
    
    console.log("=== ALLOWING FORM SUBMISSION ===")
    // Don't prevent default - let form submit normally
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

  clearAvailability(event) {
    console.log("=== CLEAR AVAILABILITY CLICKED ===")
    console.log("Event target:", event.target)
    console.log("Event target dataset:", event.target.dataset)
    
    const confirmMessage = event.target.dataset.confirm
    if (confirmMessage && !confirm(confirmMessage)) {
      console.log("User cancelled confirmation")
      return
    }

    const serviceId = event.target.dataset.serviceId
    console.log("Service ID from dataset:", serviceId)
    
    if (!serviceId) {
      console.error("No service ID found in dataset")
      console.log("Available dataset keys:", Object.keys(event.target.dataset))
      return
    }

    console.log("Clearing availability for service:", serviceId)

    // Make AJAX request to clear availability
    fetch(`/manage/services/${serviceId}/clear_availability`, {
      method: 'PATCH',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
        'Accept': 'application/json'
      }
    })
    .then(response => response.json())
    .then(data => {
      console.log("Clear availability response:", data)
      if (data.status === 'success') {
        // Show success message without reloading page
        this.showSuccessMessage(data.message)
        // Update UI to reflect cleared availability
        this.updateAvailabilityUI()
      } else {
        console.error("Failed to clear availability:", data)
        alert("Failed to clear availability. Please try again.")
      }
    })
    .catch(error => {
      console.error("Error clearing availability:", error)
      alert("An error occurred while clearing availability. Please try again.")
    })
  }

  showSuccessMessage(message) {
    // Create a temporary success message
    const successDiv = document.createElement('div')
    successDiv.className = 'fixed top-4 right-4 bg-green-100 border border-green-400 text-green-700 px-4 py-3 rounded z-50'
    successDiv.textContent = message
    document.body.appendChild(successDiv)

    // Remove after 3 seconds
    setTimeout(() => {
      if (successDiv.parentNode) {
        successDiv.parentNode.removeChild(successDiv)
      }
    }, 3000)
  }

  updateAvailabilityUI() {
    // Debug: log that UI update is invoked
    console.log("=== updateAvailabilityUI invoked ===")
    // Try to find the status element directly
    const statusEl = this.element.querySelector('[data-service-form-target="availabilityStatus"]')
    if (statusEl) {
      statusEl.innerHTML = '<span class="text-gray-500">Enforcement disabled</span> - service available when staff are available'
    } else {
      console.warn("availabilityStatus element not found")
    }
  }
} 