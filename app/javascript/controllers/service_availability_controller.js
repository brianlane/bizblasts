// Service Availability Controller
// Handles client-side validation, UI interactions, and real-time feedback
// for service availability management

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "form",
    "submitButton", 
    "errorsList",
    "dayContent",
    "slotsContainer",
    "timeSlot",
    "startTimeInput",
    "endTimeInput",
    "calendarPreview",
    "availabilityContainer"
  ]
  
  static values = {
    serviceName: String
  }

  connect() {
    console.log(`Service Availability Controller connected for: ${this.serviceNameValue}`)
    console.log('Controller element:', this.element)
    console.log('Available targets:', this.targets)
    
    // Set initial button state - only show Configure button
    this.initializeButtonState()
    
    this.initializeCollapsibleDays()
    this.validateAllTimeSlots()
    
    // Prevent double initialization
    if (this.element.dataset.initialized) return
    this.element.dataset.initialized = "true"
  }

  disconnect() {
    console.log("Service Availability Controller disconnected")
    delete this.element.dataset.initialized
  }

  // Initialize button state - ensure only Configure button is visible initially
  initializeButtonState() {
    const configureBtn = document.getElementById('configure-availability-btn')
    const disableBtn = document.getElementById('disable-availability-btn')
    const container = document.getElementById('availability-form-container')
    
    if (configureBtn && disableBtn && container) {
      // Initially: show Configure button, hide Disable button, hide form
      configureBtn.style.display = 'inline-flex'
      disableBtn.style.display = 'none'
      container.classList.add('hidden')
    }
  }

  // Initialize collapsible day sections (mobile-first)
  initializeCollapsibleDays() {
    if (window.innerWidth < 1024) {
      this.dayContentTargets.forEach(content => {
        content.style.display = 'none'
      })
      
      this.element.querySelectorAll('.day-chevron').forEach(chevron => {
        chevron.style.transform = 'rotate(-90deg)'
      })
    }
  }

  // Toggle day section visibility
  toggleDay(event) {
    const day = event.currentTarget.dataset.day
    const content = this.element.querySelector(`.day-content[data-day="${day}"]`)
    const chevron = event.currentTarget.querySelector('.day-chevron')
    
    if (content.style.display === 'none') {
      content.style.display = 'block'
      chevron.style.transform = 'rotate(0deg)'
    } else {
      content.style.display = 'none'  
      chevron.style.transform = 'rotate(-90deg)'
    }
  }

  // Toggle full day availability
  toggleFullDay(event) {
    const day = event.target.dataset.day
    const slotsContainer = this.element.querySelector(`#${day}-slots`)
    const addButton = this.element.querySelector(`[data-day="${day}"].add-slot-btn`)
    
    this.updateSlotsVisibility(event.target, slotsContainer, addButton, day)
  }

  // Update slots container visibility based on full day checkbox
  updateSlotsVisibility(checkbox, slotsContainer, addButton, day) {
    if (checkbox.checked) {
      // Hide time slots when full day is checked
      slotsContainer.style.display = 'none'
      addButton.style.display = 'none'
      
      // Clear existing time slots to prevent conflicts
      const timeSlots = slotsContainer.querySelectorAll('.time-slot-row')
      timeSlots.forEach(slot => slot.remove())
      
    } else {
      // Show time slots when full day is unchecked  
      slotsContainer.style.display = 'block'
      addButton.style.display = 'block'
      
      // Add default slot if none exist
      if (slotsContainer.children.length === 0) {
        this.addTimeSlotToContainer(day, slotsContainer)
      }
    }
    
    this.validateAllTimeSlots()
  }

  // Add new time slot
  addTimeSlot(event) {
    const day = event.currentTarget.dataset.day
    const slotsContainer = this.element.querySelector(`#${day}-slots`)
    this.addTimeSlotToContainer(day, slotsContainer)
    this.validateAllTimeSlots()
  }

  // Helper to add time slot HTML to container
  addTimeSlotToContainer(day, slotsContainer) {
    const index = slotsContainer.children.length
    
    // Determine parameter prefix based on whether the availability fields are nested
    // inside a service form (e.g., service[availability][monday][0]...) or used as a
    // standalone availability form (e.g., availability[monday][0]...). This ensures the
    // submitted params match the structure expected by the corresponding controller.
    const isNestedForm = this.element.closest('form').querySelector('input[name*="service["]') !== null

    // Nested service form -> service[availability][day][index]
    // Stand-alone availability form -> availability[day][index]
    const namePrefix = isNestedForm
      ? `service[availability][${day}][${index}]`
      : `availability[${day}][${index}]`
    
    const slotHtml = `
      <div class="time-slot-row" data-service-availability-target="timeSlot">
        <input type="hidden" 
               name="${namePrefix}[id]" 
               value="${index}" />
        
        <div class="flex items-center gap-2">
          <input type="time"
                 name="${namePrefix}[start]"
                 value="09:00"
                 class="time-input flex-1 max-w-[120px] px-2 py-2 text-sm border border-gray-300 rounded-md focus:outline-none focus:ring-1 focus:ring-blue-500 focus:border-blue-500"
                 placeholder="09:00"
                 data-action="change->service-availability#validateTimeSlot"
                 data-service-availability-target="startTimeInput" />
          
          <span class="text-gray-500 text-sm font-medium">→</span>
          
          <input type="time"
                 name="${namePrefix}[end]"
                 value="17:00"
                 class="time-input flex-1 max-w-[120px] px-2 py-2 text-sm border border-gray-300 rounded-md focus:outline-none focus:ring-1 focus:ring-blue-500 focus:border-blue-500"
                 placeholder="17:00"
                 data-action="change->service-availability#validateTimeSlot"
                 data-service-availability-target="endTimeInput" />
          
          <button type="button" 
                  class="p-2 text-red-600 hover:text-red-800 hover:bg-red-50 rounded-md transition-colors"
                  title="Remove time slot"
                  data-action="click->service-availability#removeTimeSlot">
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"/>
            </svg>
          </button>
        </div>
      </div>
    `
    
    slotsContainer.insertAdjacentHTML('beforeend', slotHtml)
  }

  // Remove time slot
  removeTimeSlot(event) {
    const timeSlotRow = event.currentTarget.closest('.time-slot-row')
    if (timeSlotRow) {
      timeSlotRow.remove()
      this.validateAllTimeSlots()
    }
  }

  // Validate individual time slot
  validateTimeSlot(event) {
    const timeSlotRow = event.currentTarget.closest('.time-slot-row')
    if (timeSlotRow) {
      this.validateTimeSlotRow(timeSlotRow)
    }
    this.updateFormValidationState()
  }

  // Validate a specific time slot row
  validateTimeSlotRow(timeSlotRow) {
    const startInput = timeSlotRow.querySelector('[data-service-availability-target="startTimeInput"]')
    const endInput = timeSlotRow.querySelector('[data-service-availability-target="endTimeInput"]')
    
    if (!startInput || !endInput) return { valid: true, errors: [] }
    
    const startTime = startInput.value
    const endTime = endInput.value
    const errors = []
    
    // Reset styles
    this.resetInputStyles(startInput)
    this.resetInputStyles(endInput)
    
    // Validate times are provided
    if (!startTime) {
      errors.push('Start time is required')
      this.markInputAsInvalid(startInput)
    }
    
    if (!endTime) {
      errors.push('End time is required')
      this.markInputAsInvalid(endInput)
    }
    
    // Validate time logic
    if (startTime && endTime) {
      if (startTime >= endTime) {
        errors.push('End time must be after start time')
        this.markInputAsInvalid(startInput)
        this.markInputAsInvalid(endInput)
      }
      
      // Check for reasonable time slots (at least 15 minutes)
      if (this.calculateMinutesDifference(startTime, endTime) < 15) {
        errors.push('Time slot must be at least 15 minutes long')
        this.markInputAsInvalid(startInput)
        this.markInputAsInvalid(endInput)
      }
    }
    
    return { valid: errors.length === 0, errors }
  }

  // Validate all time slots
  validateAllTimeSlots() {
    const allErrors = []
    const timeSlots = this.timeSlotTargets
    
    timeSlots.forEach((timeSlot, index) => {
      const result = this.validateTimeSlotRow(timeSlot)
      if (!result.valid) {
        result.errors.forEach(error => {
          allErrors.push(`Row ${index + 1}: ${error}`)
        })
      }
    })
    
    // Check for overlapping slots within same day
    this.validateOverlappingSlots(allErrors)
    
    // Update error display
    this.updateErrorDisplay(allErrors)
    
    return allErrors.length === 0
  }

  // Check for overlapping time slots within the same day
  validateOverlappingSlots(allErrors) {
    const dayContainers = this.slotsContainerTargets
    
    dayContainers.forEach(container => {
      const day = container.dataset.day
      const timeSlots = container.querySelectorAll('.time-slot-row')
      const slots = []
      
      timeSlots.forEach(slot => {
        const startInput = slot.querySelector('[data-service-availability-target="startTimeInput"]')
        const endInput = slot.querySelector('[data-service-availability-target="endTimeInput"]')
        
        if (startInput?.value && endInput?.value) {
          slots.push({
            start: startInput.value,
            end: endInput.value,
            element: slot
          })
        }
      })
      
      // Check for overlaps
      for (let i = 0; i < slots.length; i++) {
        for (let j = i + 1; j < slots.length; j++) {
          if (this.timeSlotsOverlap(slots[i], slots[j])) {
            allErrors.push(`${day.charAt(0).toUpperCase() + day.slice(1)}: Overlapping time slots detected`)
            this.markInputAsInvalid(slots[i].element.querySelector('[data-service-availability-target="startTimeInput"]'))
            this.markInputAsInvalid(slots[i].element.querySelector('[data-service-availability-target="endTimeInput"]'))
            this.markInputAsInvalid(slots[j].element.querySelector('[data-service-availability-target="startTimeInput"]'))
            this.markInputAsInvalid(slots[j].element.querySelector('[data-service-availability-target="endTimeInput"]'))
          }
        }
      }
    })
  }

  // Check if two time slots overlap
  timeSlotsOverlap(slot1, slot2) {
    const start1 = this.timeToMinutes(slot1.start)
    const end1 = this.timeToMinutes(slot1.end)
    const start2 = this.timeToMinutes(slot2.start)
    const end2 = this.timeToMinutes(slot2.end)
    
    return (start1 < end2 && end1 > start2)
  }

  // Convert time string to minutes since midnight
  timeToMinutes(timeStr) {
    const [hours, minutes] = timeStr.split(':').map(Number)
    return hours * 60 + minutes
  }

  // Calculate difference between two times in minutes
  calculateMinutesDifference(startTime, endTime) {
    return this.timeToMinutes(endTime) - this.timeToMinutes(startTime)
  }

  // Mark input as invalid
  markInputAsInvalid(input) {
    input.classList.remove('border-gray-300', 'focus:border-blue-500', 'focus:ring-blue-500')
    input.classList.add('border-red-300', 'focus:border-red-500', 'focus:ring-red-500', 'bg-red-50')
  }

  // Reset input styles to default
  resetInputStyles(input) {
    input.classList.remove('border-red-300', 'focus:border-red-500', 'focus:ring-red-500', 'bg-red-50')
    input.classList.add('border-gray-300', 'focus:border-blue-500', 'focus:ring-blue-500')
  }

  // Update error display
  updateErrorDisplay(errors) {
    const errorsContainer = this.element.querySelector('#availability-errors')
    const errorsList = this.errorsListTarget
    
    if (errors.length > 0) {
      // Show errors
      errorsContainer.classList.remove('hidden')
      errorsList.innerHTML = errors.map(error => `<li>${error}</li>`).join('')
    } else {
      // Hide errors
      errorsContainer.classList.add('hidden')
      errorsList.innerHTML = ''
    }
  }

  // Update overall form validation state
  updateFormValidationState() {
    const isValid = this.validateAllTimeSlots()
    
    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.disabled = !isValid
      
      if (isValid) {
        this.submitButtonTarget.classList.remove('opacity-50', 'cursor-not-allowed')
        this.submitButtonTarget.classList.add('hover:bg-blue-700')
      } else {
        this.submitButtonTarget.classList.add('opacity-50', 'cursor-not-allowed')
        this.submitButtonTarget.classList.remove('hover:bg-blue-700')
      }
    }
  }

  // Form validation before submit
  validateForm(event) {
    const isValid = this.validateAllTimeSlots()
    
    if (!isValid) {
      event.preventDefault()
      
      // Show a user-friendly message
      this.showValidationMessage('Please fix the validation errors before saving.')
      
      // Scroll to first error
      const firstErrorInput = this.element.querySelector('.border-red-300')
      if (firstErrorInput) {
        firstErrorInput.scrollIntoView({ behavior: 'smooth', block: 'center' })
        firstErrorInput.focus()
      }
      
      return false
    }
    
    // Show loading state
    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.disabled = true
      this.submitButtonTarget.textContent = 'Saving...'
    }
    
    return true
  }

  // Show validation message
  showValidationMessage(message) {
    // Create temporary alert if doesn't exist
    let alert = this.element.querySelector('.validation-alert')
    if (!alert) {
      alert = document.createElement('div')
      alert.className = 'validation-alert fixed top-4 right-4 bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded z-50'
      alert.innerHTML = `
        <div class="flex items-center">
          <svg class="w-4 h-4 mr-2" fill="currentColor" viewBox="0 0 20 20">
            <path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7 4a1 1 0 11-2 0 1 1 0 012 0zm-1-9a1 1 0 00-1 1v4a1 1 0 102 0V6a1 1 0 00-1-1z" clip-rule="evenodd"/>
          </svg>
          <span>${message}</span>
        </div>
      `
      document.body.appendChild(alert)
      
      // Auto remove after 5 seconds
      setTimeout(() => {
        if (alert && alert.parentNode) {
          alert.remove()
        }
      }, 5000)
    }
  }

  // Handle window resize for responsive behavior
  handleResize = () => {
    this.initializeCollapsibleDays()
  }

  // Show the availability configuration form
  showAvailabilityForm(event) {
    event.preventDefault()
    
    const container = document.getElementById('availability-form-container')
    const configureBtn = document.getElementById('configure-availability-btn')
    const disableBtn = document.getElementById('disable-availability-btn')
    
    if (container) {
      container.classList.remove('hidden')
      
      // Hide the configure button and show the disable button
      configureBtn.style.display = 'none'
      disableBtn.style.display = 'inline-flex'
      
      // Initialize collapsible days for the newly shown form
      this.initializeCollapsibleDays()
    }
  }

  // Hide the availability configuration form
  hideAvailabilityForm(event) {
    event.preventDefault()
    
    const container = document.getElementById('availability-form-container')
    const configureBtn = document.getElementById('configure-availability-btn')
    const disableBtn = document.getElementById('disable-availability-btn')
    
    if (container) {
      container.classList.add('hidden')
      
      // Hide the disable button and show the configure button
      disableBtn.style.display = 'none'
      configureBtn.style.display = 'inline-flex'
      
      // Clear any form data when hiding
      this.clearAvailabilityFormData(container)
      
      // Clear any validation errors
      this.updateErrorDisplay([])
    }
  }

  // Clear form data when hiding the availability form
  clearAvailabilityFormData(container) {
    // Clear all time inputs
    const timeInputs = container.querySelectorAll('input[type="time"]')
    timeInputs.forEach(input => {
      input.value = ''
    })
    
    // Uncheck all full day checkboxes
    const fullDayCheckboxes = container.querySelectorAll('input[name*="full_day"]')
    fullDayCheckboxes.forEach(checkbox => {
      if (checkbox.type === 'checkbox') {
        checkbox.checked = false
      }
    })
    
    // Remove all dynamically added time slots, keep only the original empty ones
    const slotsContainers = container.querySelectorAll('[data-service-availability-target="slotsContainer"]')
    slotsContainers.forEach(slotsContainer => {
      slotsContainer.innerHTML = '<!-- Initially empty - user can add slots using the button below -->'
    })
  }
}