import { Controller } from "@hotwired/stimulus"

// Stimulus controller for async Place ID extraction from Google Maps URLs
export default class extends Controller {
  static targets = ["input", "result", "placeIdField", "lookupButton", "spinner", "progressMessage"]

  connect() {
    console.log("Place ID Lookup controller connected")
    this.pollingInterval = null
    this.pollCount = 0
    this.maxPolls = 30 // Max 30 polls (60 seconds at 2s intervals)
  }

  disconnect() {
    this.stopPolling()
  }

  async lookup(event) {
    event.preventDefault()

    const input = this.inputTarget.value.trim()

    if (!input) {
      this.showError("Please enter a Google Maps URL")
      return
    }

    // Validate it's a Google Maps URL
    if (!input.includes('google.com/maps')) {
      this.showError("Please enter a valid Google Maps URL")
      return
    }

    // Show loading state
    this.setLoading(true)
    this.clearMessages()
    this.showInfo("Starting extraction... This may take 5-10 seconds.")

    try {
      const response = await fetch('/manage/settings/integrations/lookup-place-id', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.csrfToken
        },
        body: JSON.stringify({ input: input })
      })

      const data = await response.json()

      if (data.success && data.job_id) {
        // Start polling for results
        this.showInfo("Extracting Place ID from Google Maps...")
        this.startPolling(data.job_id)
      } else {
        this.setLoading(false)
        this.showError(data.error || 'Failed to start extraction')
      }
    } catch (error) {
      console.error('Place ID lookup error:', error)
      this.setLoading(false)
      this.showError('An error occurred. Please try again.')
    }
  }

  startPolling(jobId) {
    this.pollCount = 0
    this.pollingInterval = setInterval(() => {
      this.checkStatus(jobId)
    }, 2000) // Poll every 2 seconds
  }

  stopPolling() {
    if (this.pollingInterval) {
      clearInterval(this.pollingInterval)
      this.pollingInterval = null
    }
  }

  async checkStatus(jobId) {
    this.pollCount++

    // Stop polling after max attempts
    if (this.pollCount > this.maxPolls) {
      this.stopPolling()
      this.setLoading(false)
      this.showError('Extraction is taking longer than expected. Please try again or use the manual method.')
      return
    }

    try {
      const response = await fetch(`/manage/settings/integrations/check-place-id-status/${jobId}`, {
        method: 'GET',
        headers: {
          'X-CSRF-Token': this.csrfToken
        }
      })

      const data = await response.json()

      if (data.status === 'completed' && data.place_id) {
        // Success! Stop polling and show result
        this.stopPolling()
        this.setLoading(false)
        this.placeIdFieldTarget.value = data.place_id
        this.showSuccess(data.message || `Place ID found: ${data.place_id}`)
        this.inputTarget.value = '' // Clear the input
      } else if (data.status === 'failed') {
        // Extraction failed
        this.stopPolling()
        this.setLoading(false)
        this.showError(data.error || 'Extraction failed. Please use the manual method below.')
      } else if (data.status === 'processing') {
        // Still processing, update message if available
        if (data.message) {
          this.showInfo(data.message)
        }
      }
    } catch (error) {
      console.error('Status check error:', error)
      this.stopPolling()
      this.setLoading(false)
      this.showError('Error checking status. Please try again.')
    }
  }

  setLoading(isLoading) {
    if (this.hasLookupButtonTarget) {
      this.lookupButtonTarget.disabled = isLoading

      if (this.hasSpinnerTarget) {
        this.spinnerTarget.classList.toggle('hidden', !isLoading)
      }

      // Update button text
      const buttonText = this.lookupButtonTarget.querySelector('.button-text')
      if (buttonText) {
        buttonText.textContent = isLoading ? 'Extracting...' : 'Find Place ID'
      }
    }
  }

  showSuccess(message) {
    if (this.hasResultTarget) {
      this.resultTarget.innerHTML = `
        <div class="w-full p-3 bg-green-50 border border-green-200 rounded-lg">
          <div class="flex items-start gap-2">
            <svg class="w-5 h-5 text-green-600 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path>
            </svg>
            <p class="text-sm text-green-800 break-words leading-snug">${message}</p>
          </div>
        </div>
      `
      this.resultTarget.classList.remove('hidden')
    }
  }

  showError(message) {
    if (this.hasResultTarget) {
      this.resultTarget.innerHTML = `
        <div class="w-full p-3 bg-red-50 border border-red-200 rounded-lg">
          <div class="flex items-start gap-2">
            <svg class="w-5 h-5 text-red-600 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
            </svg>
            <p class="text-sm text-red-800 break-words leading-snug">${message}</p>
          </div>
        </div>
      `
      this.resultTarget.classList.remove('hidden')
    }
  }

  showInfo(message) {
    if (this.hasResultTarget) {
      this.resultTarget.innerHTML = `
        <div class="w-full p-3 bg-blue-50 border border-blue-200 rounded-lg">
          <div class="flex items-start gap-2">
            <svg class="w-5 h-5 text-blue-600 flex-shrink-0 animate-spin" fill="none" viewBox="0 0 24 24">
              <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
              <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
            </svg>
            <p class="text-sm text-blue-800 break-words leading-snug">${message}</p>
          </div>
        </div>
      `
      this.resultTarget.classList.remove('hidden')
    }
  }

  clearMessages() {
    if (this.hasResultTarget) {
      this.resultTarget.innerHTML = ''
      this.resultTarget.classList.add('hidden')
    }
  }

  get csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ''
  }
}
