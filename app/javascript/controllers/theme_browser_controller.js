import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="theme-browser"
export default class extends Controller {
  static targets = ["previewModal", "previewFrame"]
  
  connect() {
    console.log('Theme browser controller connected')
    this.currentThemeId = null
    this.setupMessageListener()
  }
  
  disconnect() {
    if (this.messageHandler) {
      window.removeEventListener('message', this.messageHandler)
    }
  }

  async previewTheme(event) {
    // Get theme ID from the closest parent element with data-theme-id
    const themeCard = event.target.closest('[data-theme-id]')
    const themeId = themeCard?.dataset.themeId
    
    if (!themeId) {
      console.error('No theme ID found')
      this.showNotification('Theme ID not found', 'error')
      return
    }
    
    console.log('Previewing theme:', themeId)
    this.currentThemeId = themeId
    
    try {
      // Clear previous iframe content
      this.previewFrameTarget.src = 'about:blank'
      
      // Show modal immediately
      this.previewModalTarget.classList.remove('hidden')
      
      // Hide navigation elements and prevent body scroll
      document.body.classList.add('modal-open')
      this.hideNavigationElements()
      
      // Load theme preview with a slight delay to ensure iframe clears
      setTimeout(() => {
        const previewUrl = `/manage/website/themes/${themeId}/preview`
        console.log('Loading preview URL:', previewUrl)
        this.previewFrameTarget.src = previewUrl
      }, 100)
      
    } catch (error) {
      console.error('Error previewing theme:', error)
      this.showNotification('Failed to load theme preview', 'error')
      this.closePreview()
    }
  }

  closePreview() {
    console.log('Closing preview')
    this.previewModalTarget.classList.add('hidden')
    this.previewFrameTarget.src = 'about:blank'
    this.currentThemeId = null
    
    // Restore navigation elements and body scroll
    document.body.classList.remove('modal-open')
    this.showNavigationElements()
  }

  activateCurrentTheme() {
    if (this.currentThemeId) {
      this.doActivateTheme(this.currentThemeId)
    }
  }

  async doActivateTheme(themeId) {
    if (!confirm('Activate this theme? This will apply the theme to your website immediately.')) {
      return
    }

    try {
      // Show loading state
      this.showNotification('Activating theme...', 'info')
      
      const response = await fetch(`/manage/website/themes/${themeId}/activate`, {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
        }
      })

      if (response.ok) {
        const result = await response.json()
        this.showNotification('Theme activated successfully! Refreshing...', 'success')
        
        // Close preview if open
        this.closePreview()
        
        // Refresh the page to show updated active theme
        setTimeout(() => {
          window.location.reload()
        }, 1500)
        
      } else {
        const error = await response.json()
        throw new Error(error.message || 'Failed to activate theme')
      }
      
    } catch (error) {
      console.error('Error activating theme:', error)
      this.showNotification(`Failed to activate theme: ${error.message}`, 'error')
    }
  }

  // Stop event propagation to prevent modal from closing when clicking inside
  stopPropagation(event) {
    event.stopPropagation()
  }

  // Keyboard navigation
  handleKeydown(event) {
    if (event.key === 'Escape') {
      this.closePreview()
    }
  }

  // Setup message listener for iframe communication
  setupMessageListener() {
    this.messageHandler = (event) => {
      if (event.data && event.data.action) {
        switch (event.data.action) {
          case 'activateTheme':
            if (event.data.themeId) {
              this.doActivateTheme(event.data.themeId)
            }
            break
          case 'closePreview':
            this.closePreview()
            break
        }
      }
    }
    window.addEventListener('message', this.messageHandler)
  }

  // Helper methods
  hideNavigationElements() {
    const elements = document.querySelectorAll('nav, .navbar, .navigation')
    elements.forEach(el => {
      el.style.display = 'none'
    })
  }

  showNavigationElements() {
    const elements = document.querySelectorAll('nav, .navbar, .navigation')
    elements.forEach(el => {
      el.style.display = ''
    })
  }

  showNotification(message, type = 'info') {
    // Create a simple notification
    const notification = document.createElement('div')
    notification.className = `fixed top-4 right-4 z-50 p-4 rounded-lg shadow-lg max-w-sm ${this.getNotificationClasses(type)}`
    notification.textContent = message
    
    document.body.appendChild(notification)
    
    // Auto-remove after 3 seconds
    setTimeout(() => {
      if (notification.parentNode) {
        notification.parentNode.removeChild(notification)
      }
    }, 3000)
  }

  getNotificationClasses(type) {
    switch (type) {
      case 'success':
        return 'bg-green-500 text-white'
      case 'error':
        return 'bg-red-500 text-white'
      case 'warning':
        return 'bg-yellow-500 text-white'
      default:
        return 'bg-blue-500 text-white'
    }
  }
} 