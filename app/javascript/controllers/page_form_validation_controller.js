import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["titleField", "titleError", "pageTypeField", "pageTypeError", "submitButton"]

  connect() {
    this.validateOnLoad()
  }

  validateOnLoad() {
    this.validateTitle()
    this.validatePageType()
  }

  validateTitle() {
    const title = this.titleFieldTarget.value.trim()
    const titleError = this.titleErrorTarget
    const field = this.titleFieldTarget

    if (title === '') {
      this.showError(field, titleError, 'Page title is required')
      return false
    } else if (title.length < 2) {
      this.showError(field, titleError, 'Page title must be at least 2 characters long')
      return false
    } else {
      this.hideError(field, titleError)
      return true
    }
  }

  validatePageType() {
    const pageType = this.pageTypeFieldTarget.value
    const pageTypeError = this.pageTypeErrorTarget
    const field = this.pageTypeFieldTarget

    if (pageType === '' || pageType === null) {
      this.showError(field, pageTypeError, 'Please select a page type')
      return false
    } else {
      this.hideError(field, pageTypeError)
      return true
    }
  }

  validateForm(event) {
    const titleValid = this.validateTitle()
    const pageTypeValid = this.validatePageType()

    if (!titleValid || !pageTypeValid) {
      event.preventDefault()
      this.showFormError('Please fix the validation errors above before submitting.')
      return false
    }

    return true
  }

  showError(field, errorElement, message) {
    field.classList.remove('border-gray-300', 'focus:border-blue-500')
    field.classList.add('border-red-300', 'focus:border-red-500')
    errorElement.textContent = message
    errorElement.classList.remove('hidden')
  }

  hideError(field, errorElement) {
    field.classList.remove('border-red-300', 'focus:border-red-500')
    field.classList.add('border-gray-300', 'focus:border-blue-500')
    errorElement.classList.add('hidden')
  }

  showFormError(message) {
    // Create or update a form-level error message
    let formError = document.querySelector('[data-form-error]')
    if (!formError) {
      formError = document.createElement('div')
      formError.setAttribute('data-form-error', 'true')
      formError.className = 'bg-red-50 border border-red-200 rounded-lg p-4 mb-4'
      formError.innerHTML = `
        <div class="flex items-center">
          <svg class="w-5 h-5 text-red-400 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"/>
          </svg>
          <p class="text-sm font-medium text-red-800"></p>
        </div>
      `
      // Insert before the form
      const form = this.element
      form.parentNode.insertBefore(formError, form)
    }
    
    const messageElement = formError.querySelector('p')
    messageElement.textContent = message
    
    // Scroll to the error
    formError.scrollIntoView({ behavior: 'smooth', block: 'center' })
    
    // Auto-hide after 5 seconds
    setTimeout(() => {
      if (formError && formError.parentNode) {
        formError.remove()
      }
    }, 5000)
  }
}