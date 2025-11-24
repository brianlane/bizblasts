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
    "disconnectButton"
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
        this.displayResults(data.businesses, data)
      } else {
        // Show no results found with manual entry option
        this.showNoResultsWithManualOption(data, this.searchInputTarget.value.trim())
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
  displayResults(businesses, searchData = {}) {
    this.searchResultsTarget.innerHTML = ''
    
    // Add search strategy notification if available
    if (searchData.search_strategy && searchData.search_strategy !== 'original') {
      const strategyNotice = this.createSearchStrategyNotice(searchData)
      this.searchResultsTarget.appendChild(strategyNotice)
    }
    
    const resultsContainer = document.createElement('div')
    resultsContainer.className = 'space-y-3 max-h-96 overflow-y-auto'
    
    businesses.forEach(business => {
      const businessElement = this.createBusinessResultElement(business)
      resultsContainer.appendChild(businessElement)
    })
    
    this.searchResultsTarget.appendChild(resultsContainer)
    this.searchResultsTarget.classList.remove('hidden')
  }

  // Create search strategy notice
  createSearchStrategyNotice(searchData) {
    const div = document.createElement('div')
    div.className = 'mb-3 p-3 bg-blue-50 border border-blue-200 rounded-lg text-sm'
    
    const strategyMessages = {
      'original_with_location': 'Found results by adding your location to the search',
      'cleaned_name': 'Found results by simplifying your business name',
      'cleaned_with_location': 'Found results by simplifying your business name and adding location',
      'core_name': 'Found results using just the core business name',
      'category_search': 'Found results by searching for your business category in your area'
    }
    
    const message = strategyMessages[searchData.search_strategy] || 'Found results using an optimized search'
    
    div.innerHTML = `
      <div class="flex items-start">
        <div class="flex-shrink-0">
          <svg class="w-4 h-4 text-blue-600 mt-0.5" fill="currentColor" viewBox="0 0 20 20">
            <path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clip-rule="evenodd"/>
          </svg>
        </div>
        <div class="ml-2">
          <p class="text-blue-800 font-medium">Smart Search</p>
          <p class="text-blue-700">${this.escapeHtml(message)}. These businesses match your search criteria.</p>
        </div>
      </div>
    `
    
    return div
  }

  // Create individual business result element
  createBusinessResultElement(business) {
    const div = document.createElement('div')
    div.className = 'p-4 border border-gray-200 rounded-lg hover:border-blue-300 cursor-pointer transition-colors bg-white'
    
    div.innerHTML = `
      <!-- Desktop Layout -->
      <div class="hidden sm:flex items-start justify-between">
        <div class="flex-1 min-w-0">
          <h4 class="font-semibold text-gray-900 text-lg">${this.escapeHtml(business.name)}</h4>
          <p class="text-gray-600 text-sm mt-1">${this.escapeHtml(business.address)}</p>
          <div class="mt-2 flex flex-wrap gap-1">
            ${business.types.slice(0, 3).map(type => 
              `<span class="px-2 py-1 bg-gray-100 text-gray-600 text-xs rounded">${this.formatBusinessType(type)}</span>`
            ).join('')}
          </div>
        </div>
        <div class="ml-4 flex-shrink-0">
          <button class="px-4 py-2 bg-blue-600 text-white text-sm rounded hover:bg-blue-700 transition-colors connect-button cursor-pointer whitespace-nowrap">
            Connect This Business
          </button>
        </div>
      </div>
      
      <!-- Mobile Layout -->
      <div class="block sm:hidden">
        <div class="mb-4">
          <h4 class="font-semibold text-gray-900 text-lg leading-tight">${this.escapeHtml(business.name)}</h4>
          <p class="text-gray-600 text-sm mt-1 leading-tight">${this.escapeHtml(business.address)}</p>
          <div class="mt-2 flex flex-wrap gap-1">
            ${business.types.slice(0, 3).map(type => 
              `<span class="px-2 py-1 bg-gray-100 text-gray-600 text-xs rounded">${this.formatBusinessType(type)}</span>`
            ).join('')}
          </div>
        </div>
        <button class="w-full px-4 py-3 bg-blue-600 text-white text-sm font-medium rounded-lg hover:bg-blue-700 transition-colors connect-button cursor-pointer">
          Connect This Business
        </button>
      </div>
    `
    
    // Add click handler for all connect buttons (desktop and mobile)
    const connectButtons = div.querySelectorAll('.connect-button')
    connectButtons.forEach(button => {
      button.addEventListener('click', (e) => {
        e.stopPropagation()
        this.connectBusiness(business.place_id, business.name)
      })
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
          <button class="flex-1 px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700 connect-preview-button cursor-pointer">
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

  /**
   * Display error message in the UI
   * Handles both direct calls and ajax:error events from Rails UJS
   * @param {string|Event} eventOrMessage - Error message string or ajax:error Event object
   * @param {Array} details - Array of error detail strings (when called directly)
   */
  showError(eventOrMessage, details = []) {
    if (!this.hasErrorMessageTarget) return

    let message, errorDetails
    
    // Check if this is being called from an ajax:error event (Event object)
    if (eventOrMessage instanceof Event) {
      const event = eventOrMessage
      
      // Extract error information from event.detail
      // Rails UJS ajax:error event structure: [xhr, status, error]
      const [xhr, status, error] = event.detail || []
      
      // Debug logging to help developers
      console.debug('[GoogleBusinessSearch] Handling ajax:error event:', {
        status,
        error,
        responseText: xhr?.responseText,
        responseJSON: xhr?.responseJSON
      })
      
      if (xhr && xhr.responseJSON) {
        // Try to get structured error from JSON response
        const responseData = xhr.responseJSON
        message = responseData.error || responseData.message || 'Connection failed'
        errorDetails = responseData.details || responseData.errors || []
      } else if (xhr && xhr.responseText) {
        // Fallback to plain text response
        try {
          const responseData = JSON.parse(xhr.responseText)
          message = responseData.error || responseData.message || 'Connection failed'
          errorDetails = responseData.details || responseData.errors || []
        } catch (e) {
          message = 'Connection failed. Please try again.'
          errorDetails = []
        }
      } else {
        // Fallback for no response data
        message = error || 'Connection failed. Please try again.'
        errorDetails = []
      }
    } else {
      // Called directly with message and details (existing behavior)
      message = eventOrMessage
      errorDetails = details
    }

    const container = this.errorMessageTarget
    // If container has a paragraph child, use it; otherwise write to container
    const textEl = container.querySelector('p') || container
    textEl.textContent = message

    // Remove any prior details list
    const existingList = container.querySelector('ul')
    if (existingList) existingList.remove()

    if (Array.isArray(errorDetails) && errorDetails.length > 0) {
      const list = document.createElement('ul')
      list.className = 'mt-2 list-disc list-inside text-sm text-red-700'
      errorDetails.forEach((d) => {
        const li = document.createElement('li')
        li.textContent = d
        list.appendChild(li)
      })
      const textWrapper = container.querySelector('.ml-3') || container
      textWrapper.appendChild(list)
    }

    container.classList.remove('hidden')
  }

  // Show no results found with manual entry option
  showNoResultsWithManualOption(data, query) {
    this.clearResults()
    
    // Create a comprehensive no results section
    const noResultsSection = document.createElement('div')
    noResultsSection.className = 'space-y-4'
    
    // Main message
    const message = data.message || 'No businesses found matching your search criteria.'
    const messageEl = document.createElement('div')
    messageEl.className = 'p-4 bg-yellow-50 border border-yellow-200 rounded-lg'
    messageEl.innerHTML = `
      <div class="flex items-start">
        <div class="flex-shrink-0">
          <svg class="w-5 h-5 text-yellow-600 mt-0.5" fill="currentColor" viewBox="0 0 20 20">
            <path fill-rule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clip-rule="evenodd"/>
          </svg>
        </div>
        <div class="ml-3">
          <h3 class="text-yellow-800 font-medium">Business Not Found</h3>
          <p class="text-yellow-700 text-sm mt-1">${this.escapeHtml(message)}</p>
        </div>
      </div>
    `
    noResultsSection.appendChild(messageEl)
    
    // Suggestions
    const suggestionsEl = document.createElement('div')
    suggestionsEl.className = 'p-4 bg-blue-50 border border-blue-200 rounded-lg'
    
    let suggestions = []
    if (query.length > 20) {
      suggestions.push("Try a shorter business name")
    }
    if (query.includes('&') || query.includes('and')) {
      suggestions.push("Remove connecting words like '&' or 'and'")
    }
    if (query.match(/detail|protection|service/i)) {
      suggestions.push("Search by business category (e.g., 'auto detail')")
    }
    suggestions.push("Try just your business name without services")
    suggestions.push("Search for nearby businesses in your category")
    
    suggestionsEl.innerHTML = `
      <div class="flex items-start">
        <div class="flex-shrink-0">
          <svg class="w-5 h-5 text-blue-600 mt-0.5" fill="currentColor" viewBox="0 0 20 20">
            <path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clip-rule="evenodd"/>
          </svg>
        </div>
        <div class="ml-3">
          <h3 class="text-blue-800 font-medium">Try These Search Tips</h3>
          <ul class="text-blue-700 text-sm mt-2 space-y-1 list-disc list-inside">
            ${suggestions.map(suggestion => `<li>${this.escapeHtml(suggestion)}</li>`).join('')}
          </ul>
        </div>
      </div>
    `
    noResultsSection.appendChild(suggestionsEl)
    
    // Manual entry option
    const manualEntryEl = document.createElement('div')
    manualEntryEl.className = 'p-4 bg-green-50 border border-green-200 rounded-lg'
    manualEntryEl.innerHTML = `
      <div class="flex items-start">
        <div class="flex-shrink-0">
          <svg class="w-5 h-5 text-green-600 mt-0.5" fill="currentColor" viewBox="0 0 20 20">
            <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd"/>
          </svg>
        </div>
        <div class="ml-3">
          <h3 class="text-green-800 font-medium">Can't Find Your Business?</h3>
          <p class="text-green-700 text-sm mt-1 mb-3">
            Some businesses exist on Google but aren't discoverable through search. If you know your business exists on Google Maps, you can connect it using its Place ID.
          </p>
          <button class="inline-flex items-center px-4 py-2 bg-green-600 text-white text-sm font-medium rounded-md hover:bg-green-700 transition-colors manual-entry-button cursor-pointer">
            <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6v6m0 0v6m0-6h6m-6 0H6"/>
            </svg>
            Connect Using Place ID
          </button>
        </div>
      </div>
    `
    
    // Add click handler for manual entry
    const manualButton = manualEntryEl.querySelector('.manual-entry-button')
    manualButton.addEventListener('click', () => {
      this.showManualEntryForm(query)
    })
    
    noResultsSection.appendChild(manualEntryEl)
    
    // Show the complete no results section
    this.searchResultsTarget.innerHTML = ''
    this.searchResultsTarget.appendChild(noResultsSection)
    this.searchResultsTarget.classList.remove('hidden')
  }

  // Show manual entry form for businesses that can't be found
  showManualEntryForm(prefillName = '') {
    this.clearResults()
    this.clearError()
    
    const manualForm = document.createElement('div')
    manualForm.className = 'p-6 bg-white border border-gray-200 rounded-lg shadow-sm'
    
    manualForm.innerHTML = `
      <div class="mb-4">
        <h3 class="text-lg font-medium text-gray-900 mb-2">Add Your Business Manually</h3>
        <p class="text-sm text-gray-600">
          If your business exists on Google Maps but can't be found through search, you can add it using its Google Place ID or by providing basic details.
        </p>
      </div>
      
      <div class="space-y-4">
        <!-- Place ID Entry -->
        <div class="border border-gray-200 rounded-lg p-4">
          <h4 class="font-medium text-gray-900 mb-2">Enter Google Place ID</h4>
          <p class="text-sm text-gray-600 mb-3">
            Find your business on <a href="https://maps.google.com" target="_blank" class="text-blue-600 hover:underline">Google Maps</a>,
            copy the URL, and we'll extract the Place ID for you.
          </p>
          <div class="space-y-3">
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-1">Google Maps URL or Place ID</label>
              <input type="text" 
                     class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500 text-sm"
                     placeholder="https://maps.google.com/... or ChIJAbCdEfGhIjKlMnOpQrStUvWxYz"
                     id="place-id-input">
            </div>
            <button type="button" 
                    class="px-4 py-2 bg-blue-600 text-white text-sm font-medium rounded-md hover:bg-blue-700 transition-colors connect-place-id-button cursor-pointer">
              Connect Using Place ID
            </button>
          </div>
        </div>
        
      </div>
      
      <div class="mt-4 pt-4 border-t border-gray-200">
        <button type="button" 
                class="text-sm text-gray-600 hover:text-gray-800 transition-colors back-to-search-button cursor-pointer">
          ← Back to Search
        </button>
      </div>
    `
    
    // Add event listeners
    const placeIdButton = manualForm.querySelector('.connect-place-id-button')
    placeIdButton.addEventListener('click', () => {
      this.handlePlaceIdEntry()
    })

    const backButton = manualForm.querySelector('.back-to-search-button')
    backButton.addEventListener('click', () => {
      this.clearResults()
      this.clearSearchInput()
    })
    
    this.searchResultsTarget.innerHTML = ''
    this.searchResultsTarget.appendChild(manualForm)
    this.searchResultsTarget.classList.remove('hidden')
  }
  
  // Handle Place ID entry
  handlePlaceIdEntry() {
    const input = document.getElementById('place-id-input')
    const value = input.value.trim()
    
    if (!value) {
      alert('Please enter a Google Maps URL or Place ID')
      return
    }
    
    // Extract Place ID from Google Maps URL if needed
    let placeId = value
    
    // If it's a Google Maps URL, try multiple extraction approaches
    if (value.includes('maps.google') || value.includes('google.com/maps')) {
      // First, try to extract coordinates and search nearby
      const coordMatch = value.match(/@([-\d.]+),([-\d.]+)/)
      if (coordMatch) {
        const latitude = parseFloat(coordMatch[1])
        const longitude = parseFloat(coordMatch[2])
        
        // Extract business name from URL
        const nameMatch = value.match(/place\/([^@/]+)/)
        let businessName = ''
        if (nameMatch) {
          businessName = decodeURIComponent(nameMatch[1]).replace(/\+/g, ' ')
        }
        
        alert(`Found coordinates in Google Maps URL: ${latitude}, ${longitude}

We'll try to find your business using coordinate-based search...`)
        
        this.searchByCoordinates(latitude, longitude, businessName)
        return
      }
      
      // If no coordinates, try Place ID extraction patterns
      const patterns = [
        /\/place\/[^/]+\/([A-Za-z0-9_-]+)/,  // New format
        /place\/([^/?#]+)/,                  // Basic format
        /\/([A-Za-z0-9_-]{27,})/,              // Long ID format
        /1s([A-Za-z0-9_-]+)/,                  // 1s parameter
        /16s%2Fg%2F([a-zA-Z0-9_-]+)/,          // Encoded ftid
        /ChIJ[A-Za-z0-9_-]+/                   // Direct ChIJ format
      ]
      
      let extracted = null
      for (const pattern of patterns) {
        const match = value.match(pattern)
        if (match) {
          extracted = match[1] || match[0]
          break
        }
      }
      
      if (extracted) {
        placeId = extracted
      } else {
        alert(`Could not extract Place ID from this Google Maps URL. 

This business may not be available through the Google Places API.`)
        return
      }
    }
    
    // Validate Place ID format - be more flexible since Google uses different formats
    if (placeId.length < 10) {
      alert('Place ID seems too short. Please check the URL or try a different option.')
      return
    }
    
    // Show loading and attempt connection
    this.showLoading()
    this.connectBusiness(placeId, 'Manual Entry').catch(error => {
      this.hideLoading()
      alert(`Connection failed: The Place ID from this Google Maps URL doesn't work with our API.

This often happens with:
• Service-area businesses (like mobile services)
• Recently added businesses
• Businesses with unverified addresses

This business may not be available through the Google Places API.`)
    })
  }
  
  // Search by coordinates extracted from Google Maps URL
  async searchByCoordinates(latitude, longitude, businessName) {
    this.showLoading()
    
    try {
      const response = await fetch(`/manage/settings/integrations/google-business/search-nearby?latitude=${latitude}&longitude=${longitude}&query=${encodeURIComponent(businessName)}`, {
        method: 'GET',
        headers: {
          'Content-Type': 'application/json',
          'X-Requested-With': 'XMLHttpRequest'
        }
      })

      const data = await response.json()

      if (data.error) {
        this.showError(`Coordinate search failed: ${data.error}`)
      } else if (data.businesses && data.businesses.length > 0) {
        // Show results with coordinate search info
        this.displayCoordinateSearchResults(data.businesses, businessName, latitude, longitude)
      } else {
        this.showError(`No businesses found near coordinates ${latitude}, ${longitude}. The business may not be available through the Google Places API.`)
      }
    } catch (error) {
      console.error('Coordinate search error:', error)
      this.showError('Coordinate search failed. Please try a different option.')
    } finally {
      this.hideLoading()
    }
  }
  
  // Display results from coordinate search
  displayCoordinateSearchResults(businesses, originalName, latitude, longitude) {
    this.searchResultsTarget.innerHTML = ''
    
    // Add notice about coordinate search
    const notice = document.createElement('div')
    notice.className = 'mb-4 p-3 bg-purple-50 border border-purple-200 rounded-lg text-sm'
    notice.innerHTML = `
      <div class="flex items-start">
        <div class="flex-shrink-0">
          <svg class="w-4 h-4 text-purple-600 mt-0.5" fill="currentColor" viewBox="0 0 20 20">
            <path fill-rule="evenodd" d="M5.05 4.05a7 7 0 119.9 9.9L10 18.9l-4.95-4.95a7 7 0 010-9.9zM10 11a2 2 0 100-4 2 2 0 000 4z" clip-rule="evenodd"/>
          </svg>
        </div>
        <div class="ml-2">
          <p class="text-purple-800 font-medium">Coordinate-Based Search</p>
          <p class="text-purple-700">Found ${businesses.length} businesses near ${latitude}, ${longitude}. Look for "${this.escapeHtml(originalName)}" below.</p>
        </div>
      </div>
    `
    this.searchResultsTarget.appendChild(notice)
    
    // Show regular results
    const resultsContainer = document.createElement('div')
    resultsContainer.className = 'space-y-3 max-h-96 overflow-y-auto'
    
    businesses.forEach(business => {
      const businessElement = this.createBusinessResultElement(business)
      resultsContainer.appendChild(businessElement)
    })
    
    this.searchResultsTarget.appendChild(resultsContainer)
    this.searchResultsTarget.classList.remove('hidden')
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