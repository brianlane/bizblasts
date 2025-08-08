// Google Business Search Controller
// Handles the interactive search and connection flow for Google Business listings

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "searchInput",
    "locationInput", 
    "searchResults",
    "searchButton",
    "loadingIndicator",
    "errorMessage",
    "connectedBusiness",
    "connectionStatus",
    "disconnectButton",
    "manualEntry"
  ]
  
  static values = {
    businessName: String,
    businessAddress: String
  }

  connect() {
    console.log('Google Business Search controller connected')
    console.log('Available targets:', this.targets)
    console.log('Has searchInputTarget:', this.hasSearchInputTarget)
    console.log('Has searchButtonTarget:', this.hasSearchButtonTarget)
    
    this.searchTimeout = null
    
    try {
      this.checkConnectionStatus()
      this.prefillSearchInput()
    } catch (error) {
      console.error('Error in connect():', error)
    }
  }

  disconnect() {
    if (this.searchTimeout) {
      clearTimeout(this.searchTimeout)
    }
  }

  // Prefill search input with business name if available
  prefillSearchInput() {
    if (this.businessNameValue && this.hasSearchInputTarget) {
      this.searchInputTarget.value = this.businessNameValue
    }
    
    if (this.businessAddressValue && this.hasLocationInputTarget) {
      this.locationInputTarget.value = this.businessAddressValue
    }
  }

  // Handle search input with debouncing
  onSearchInput() {
    if (this.searchTimeout) {
      clearTimeout(this.searchTimeout)
    }
    
    this.searchTimeout = setTimeout(() => {
      this.performSearch()
    }, 500) // 500ms delay
  }

  // Handle manual search button click
  onSearchClick(event) {
    console.log('Search button clicked', event)
    event.preventDefault()
    
    try {
      this.performSearch()
    } catch (error) {
      console.error('Error in onSearchClick:', error)
    }
  }

  // Perform the actual search
  async performSearch() {
    const query = this.searchInputTarget.value.trim()
    const location = this.hasLocationInputTarget ? this.locationInputTarget.value.trim() : ''
    
    if (!query) {
      this.clearResults()
      return
    }

    this.showLoading()
    this.clearError()

    try {
      const params = new URLSearchParams({ query })
      if (location) {
        params.append('location', location)
      }

      const response = await fetch(`/manage/settings/integrations/google-business/search?${params}`, {
        method: 'GET',
        headers: {
          'Content-Type': 'application/json',
          'X-Requested-With': 'XMLHttpRequest'
        }
      })

      const data = await response.json()

      if (data.error) {
        console.error('Search API Error:', data)
        let errorMessage = data.error
        if (data.debug_error) {
          errorMessage += ` (Debug: ${data.debug_error})`
        }
        this.showError(errorMessage)
        this.clearResults()
      } else if (data.businesses && data.businesses.length > 0) {
        this.displayResults(data.businesses)
      } else {
        this.showError('No businesses found. Try adjusting your search terms or location.')
        this.clearResults()
      }
    } catch (error) {
      console.error('Search error:', error)
      this.showError('Search failed. Please try again.')
      this.clearResults()
    } finally {
      this.hideLoading()
    }
  }

  // Display search results
  displayResults(businesses) {
    this.searchResultsTarget.innerHTML = ''
    
    const resultsContainer = document.createElement('div')
    resultsContainer.className = 'space-y-3 max-h-96 overflow-y-auto'
    
    businesses.forEach(business => {
      const businessElement = this.createBusinessResultElement(business)
      resultsContainer.appendChild(businessElement)
    })
    
    this.searchResultsTarget.appendChild(resultsContainer)
    this.searchResultsTarget.classList.remove('hidden')
  }

  // Create individual business result element
  createBusinessResultElement(business) {
    const div = document.createElement('div')
    div.className = 'p-4 border border-gray-200 rounded-lg hover:border-blue-300 cursor-pointer transition-colors bg-white'
    
    div.innerHTML = `
      <div class="flex items-start justify-between">
        <div class="flex-1">
          <h4 class="font-semibold text-gray-900 text-lg">${this.escapeHtml(business.name)}</h4>
          <p class="text-gray-600 text-sm mt-1">${this.escapeHtml(business.address)}</p>
          <div class="mt-2 flex flex-wrap gap-1">
            ${business.types.slice(0, 3).map(type => 
              `<span class="px-2 py-1 bg-gray-100 text-gray-600 text-xs rounded">${this.formatBusinessType(type)}</span>`
            ).join('')}
          </div>
        </div>
        <button class="ml-4 px-4 py-2 bg-blue-600 text-white text-sm rounded hover:bg-blue-700 transition-colors connect-button">
          Connect This Business
        </button>
      </div>
    `
    
    // Add click handler for the connect button
    const connectButton = div.querySelector('.connect-button')
    connectButton.addEventListener('click', (e) => {
      e.stopPropagation()
      this.connectBusiness(business.place_id, business.name)
    })
    
    // Add click handler for the whole div (for preview)
    div.addEventListener('click', () => {
      this.previewBusiness(business.place_id)
    })
    
    return div
  }

  // Preview business details
  async previewBusiness(placeId) {
    try {
      const response = await fetch(`/manage/settings/integrations/google-business/details/${placeId}`, {
        method: 'GET',
        headers: {
          'Content-Type': 'application/json',
          'X-Requested-With': 'XMLHttpRequest'
        }
      })

      const data = await response.json()

      if (data.success && data.business) {
        this.showBusinessPreview(data.business)
      }
    } catch (error) {
      console.error('Preview error:', error)
    }
  }

  // Show business preview modal or section
  showBusinessPreview(business) {
    // Create a simple preview popup
    const preview = document.createElement('div')
    preview.className = 'fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50'
    
    preview.innerHTML = `
      <div class="bg-white rounded-lg p-6 max-w-md mx-4 max-h-96 overflow-y-auto">
        <div class="flex justify-between items-start mb-4">
          <h3 class="text-lg font-semibold">${this.escapeHtml(business.name)}</h3>
          <button class="text-gray-400 hover:text-gray-600 close-preview">&times;</button>
        </div>
        
        <div class="space-y-3">
          ${business.address ? `<p class="text-gray-600"><strong>Address:</strong> ${this.escapeHtml(business.address)}</p>` : ''}
          ${business.phone ? `<p class="text-gray-600"><strong>Phone:</strong> ${this.escapeHtml(business.phone)}</p>` : ''}
          ${business.website ? `<p class="text-gray-600"><strong>Website:</strong> <a href="${this.escapeHtml(business.website)}" target="_blank" class="text-blue-600 hover:underline">${this.escapeHtml(business.website)}</a></p>` : ''}
          ${business.rating ? `<p class="text-gray-600"><strong>Rating:</strong> ${business.rating}/5 (${business.total_ratings || 0} reviews)</p>` : ''}
          
          ${business.recent_reviews && business.recent_reviews.length > 0 ? `
            <div>
              <strong class="text-gray-700">Recent Reviews:</strong>
              <div class="mt-2 space-y-2">
                ${business.recent_reviews.map(review => `
                  <div class="text-sm border-l-2 border-gray-200 pl-3">
                    <div class="font-medium">${this.escapeHtml(review.author)} - ${review.rating}/5</div>
                    <p class="text-gray-600 mt-1">${this.escapeHtml(review.text)}</p>
                  </div>
                `).join('')}
              </div>
            </div>
          ` : ''}
        </div>
        
        <div class="mt-6 flex gap-3">
          <button class="flex-1 px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700 connect-preview-button">
            Connect This Business
          </button>
          <button class="px-4 py-2 bg-gray-200 text-gray-700 rounded hover:bg-gray-300 close-preview">
            Cancel
          </button>
        </div>
      </div>
    `
    
    // Add event listeners
    preview.querySelectorAll('.close-preview').forEach(btn => {
      btn.addEventListener('click', () => document.body.removeChild(preview))
    })
    
    preview.querySelector('.connect-preview-button').addEventListener('click', () => {
      this.connectBusiness(business.place_id, business.name)
      document.body.removeChild(preview)
    })
    
    document.body.appendChild(preview)
  }

  // Connect to selected business
  async connectBusiness(placeId, businessName) {
    this.showLoading()
    this.clearError()

    try {
      const response = await fetch('/manage/settings/integrations/google-business/connect', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Requested-With': 'XMLHttpRequest',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
        },
        body: JSON.stringify({
          place_id: placeId,
          business_name: businessName
        })
      })

      const data = await response.json()

      if (data.success) {
        this.showConnectionSuccess(data.business)
        this.clearResults()
        this.clearSearchInput()
      } else {
        const message = data.error || 'Failed to connect business'
        const details = Array.isArray(data.details) ? data.details : []
        this.showError(message, details)
      }
    } catch (error) {
      console.error('Connection error:', error)
      this.showError('Connection failed. Please try again.')
    } finally {
      this.hideLoading()
    }
  }

  // Disconnect from Google Business
  async disconnectBusiness() {
    if (!confirm('Are you sure you want to disconnect your Google Business listing? This will disable review requests and review display.')) {
      return
    }

    try {
      const response = await fetch('/manage/settings/integrations/google-business/disconnect', {
        method: 'DELETE',
        headers: {
          'Content-Type': 'application/json',
          'X-Requested-With': 'XMLHttpRequest',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
        }
      })

      const data = await response.json()

      if (data.success) {
        this.showDisconnectionSuccess()
      } else {
        this.showError(data.error || 'Failed to disconnect business')
      }
    } catch (error) {
      console.error('Disconnection error:', error)
      this.showError('Disconnection failed. Please try again.')
    }
  }

  // Check current connection status
  async checkConnectionStatus() {
    try {
      const response = await fetch('/manage/settings/integrations/google-business/status', {
        method: 'GET',
        headers: {
          'Content-Type': 'application/json',
          'X-Requested-With': 'XMLHttpRequest'
        }
      })

      const data = await response.json()

      if (data.connected && data.business) {
        this.showConnectionSuccess(data.business)
      } else if (data.connected && data.warning) {
        this.showConnectionWarning(data.warning)
      }
    } catch (error) {
      console.error('Status check error:', error)
    }
  }

  // Show connection success state
  showConnectionSuccess(business) {
    if (this.hasConnectedBusinessTarget) {
      this.connectedBusinessTarget.innerHTML = `
        <div class="bg-green-50 border border-green-200 rounded-lg p-4">
          <div class="flex items-start justify-between">
            <div class="flex items-center">
              <div class="w-10 h-10 bg-green-100 rounded-full flex items-center justify-center">
                <svg class="w-5 h-5 text-green-600" fill="currentColor" viewBox="0 0 20 20">
                  <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd"/>
                </svg>
              </div>
              <div class="ml-3">
                <h4 class="text-green-800 font-medium">${this.escapeHtml(business.name)}</h4>
                <p class="text-green-700 text-sm">${this.escapeHtml(business.address || '')}</p>
                ${business.rating ? `<p class="text-green-600 text-xs mt-1">${business.rating}/5 stars • ${business.total_ratings || 0} reviews</p>` : ''}
              </div>
            </div>
            <button class="text-red-600 hover:text-red-800 text-sm disconnect-button cursor-pointer">
              Disconnect
            </button>
          </div>
          <div class="mt-3 text-sm text-green-700">
            ✅ Google reviews will now appear on your public business page<br>
            ✅ Review request emails will be sent to customers after payments
          </div>
        </div>
      `
      
      // Add disconnect handler
      this.connectedBusinessTarget.querySelector('.disconnect-button').addEventListener('click', () => {
        this.disconnectBusiness()
      })
      
      this.connectedBusinessTarget.classList.remove('hidden')
    }
  }

  // Show connection warning
  showConnectionWarning(warning) {
    if (this.hasConnectedBusinessTarget) {
      this.connectedBusinessTarget.innerHTML = `
        <div class="bg-yellow-50 border border-yellow-200 rounded-lg p-4">
          <div class="flex items-start">
            <div class="w-10 h-10 bg-yellow-100 rounded-full flex items-center justify-center">
              <svg class="w-5 h-5 text-yellow-600" fill="currentColor" viewBox="0 0 20 20">
                <path fill-rule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clip-rule="evenodd"/>
              </svg>
            </div>
            <div class="ml-3 flex-1">
              <h4 class="text-yellow-800 font-medium">Google Business Connection Issue</h4>
              <p class="text-yellow-700 text-sm mt-1">${this.escapeHtml(warning)}</p>
              <button class="mt-2 text-blue-600 hover:text-blue-800 text-sm disconnect-button">
                Reconnect Business
              </button>
            </div>
          </div>
        </div>
      `
      
      // Add reconnect handler (which is essentially disconnect + search again)
      this.connectedBusinessTarget.querySelector('.disconnect-button').addEventListener('click', () => {
        this.disconnectBusiness()
      })
      
      this.connectedBusinessTarget.classList.remove('hidden')
    }
  }

  // Show disconnection success
  showDisconnectionSuccess() {
    if (this.hasConnectedBusinessTarget) {
      this.connectedBusinessTarget.classList.add('hidden')
    }
    this.clearSearchInput()
  }

  // Utility methods
  toggleManualEntry() {
    if (this.hasManualEntryTarget) {
      this.manualEntryTarget.classList.toggle('hidden')
    }
  }
  showLoading() {
    if (this.hasLoadingIndicatorTarget) {
      this.loadingIndicatorTarget.classList.remove('hidden')
    }
    if (this.hasSearchButtonTarget) {
      this.searchButtonTarget.disabled = true
    }
  }

  hideLoading() {
    if (this.hasLoadingIndicatorTarget) {
      this.loadingIndicatorTarget.classList.add('hidden')
    }
    if (this.hasSearchButtonTarget) {
      this.searchButtonTarget.disabled = false
    }
  }

  showError(message, details = []) {
    if (!this.hasErrorMessageTarget) return

    const container = this.errorMessageTarget
    // If container has a paragraph child, use it; otherwise write to container
    const textEl = container.querySelector('p') || container
    textEl.textContent = message

    // Remove any prior details list
    const existingList = container.querySelector('ul')
    if (existingList) existingList.remove()

    if (Array.isArray(details) && details.length > 0) {
      const list = document.createElement('ul')
      list.className = 'mt-2 list-disc list-inside text-sm text-red-700'
      details.forEach((d) => {
        const li = document.createElement('li')
        li.textContent = d
        list.appendChild(li)
      })
      const textWrapper = container.querySelector('.ml-3') || container
      textWrapper.appendChild(list)
    }

    container.classList.remove('hidden')
  }

  clearError() {
    if (this.hasErrorMessageTarget) {
      this.errorMessageTarget.classList.add('hidden')
    }
  }

  clearResults() {
    if (this.hasSearchResultsTarget) {
      this.searchResultsTarget.innerHTML = ''
      this.searchResultsTarget.classList.add('hidden')
    }
  }

  clearSearchInput() {
    if (this.hasSearchInputTarget) {
      this.searchInputTarget.value = ''
    }
  }

  escapeHtml(text) {
    const div = document.createElement('div')
    div.textContent = text
    return div.innerHTML
  }

  formatBusinessType(type) {
    return type.split('_').map(word => 
      word.charAt(0).toUpperCase() + word.slice(1).toLowerCase()
    ).join(' ')
  }
}