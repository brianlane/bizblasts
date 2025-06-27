/**
 * Sortable Controller - Reusable Drag & Drop Sorting
 * 
 * This Stimulus controller provides drag and drop sorting functionality
 * for products, services, and other sortable items in the business manager.
 * 
 * Usage:
 * <div data-controller="sortable" 
 *      data-sortable-update-url-value="/manage/products/:id/update_position"
 *      data-sortable-item-type-value="product">
 *   <div data-sortable-target="item" data-item-id="1">Item 1</div>
 *   <div data-sortable-target="item" data-item-id="2">Item 2</div>
 * </div>
 */

import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

export default class extends Controller {
  static targets = ["item"]
  static values = { 
    updateUrl: String,
    itemType: String
  }

  connect() {
    // Always initialize arrow buttons (they're safe to re-initialize)
    this.initializeArrowButtons()
    
    // Only prevent sortable re-initialization
    if (this.element.hasAttribute('data-sortable-initialized')) {
      console.log('Sortable already initialized, skipping sortable setup')
      return
    }
    
    this.initializeSortable()
    this.lastUpdateRequest = null
    this.element.setAttribute('data-sortable-initialized', 'true')
  }

  disconnect() {
    if (this.sortable) {
      this.sortable.destroy()
      this.sortable = null
    }
    if (this.sortables) {
      this.sortables.forEach(sortable => sortable.destroy())
      this.sortables = null
    }
    // Remove arrow button event listener
    if (this.arrowClickHandler) {
      this.element.removeEventListener('click', this.arrowClickHandler)
      this.arrowClickHandler = null
    }
    // Clear initialization flag
    this.element.removeAttribute('data-sortable-initialized')
  }

  initializeSortable() {
    // Find all containers that should be sortable within this controller
    const containers = this.element.querySelectorAll('.lg\\:hidden, tbody')
    
    if (containers.length === 0) {
      // If no specific containers, use the whole element
      this.sortable = Sortable.create(this.element, {
        animation: 150,
        ghostClass: 'sortable-ghost',
        chosenClass: 'sortable-chosen',
        dragClass: 'sortable-drag',
        handle: '.sortable-handle',
        onEnd: this.handleSortEnd.bind(this)
      })
    } else {
      // Create sortable for each container
      this.sortables = Array.from(containers).map(container => {
        return Sortable.create(container, {
          group: 'shared', // Same group for mobile and desktop
          animation: 150,
          ghostClass: 'sortable-ghost',
          chosenClass: 'sortable-chosen',
          dragClass: 'sortable-drag',
          handle: '.sortable-handle',
          onEnd: this.handleSortEnd.bind(this)
        })
      })
    }
  }

  async handleSortEnd(event) {
    const item = event.item
    const itemId = item.dataset.itemId
    const newPosition = event.newIndex
    
    if (!itemId) {
      console.error('No item ID found for sortable item')
      return
    }

    // Prevent duplicate requests
    const requestKey = `${itemId}-${newPosition}-${Date.now()}`
    if (this.lastUpdateRequest === requestKey) {
      return
    }
    this.lastUpdateRequest = requestKey

    try {
      const response = await this.updatePosition(itemId, newPosition)
      
      if (response.status === 'success') {
        this.showNotification(response.message || 'Position updated successfully', 'success')
      } else {
        throw new Error(response.message || 'Failed to update position')
      }
    } catch (error) {
      console.error('Error updating position:', error)
      this.showNotification(error.message || 'Failed to update position', 'error')
      
      // Revert the visual change
      this.revertSortChange(event)
    }
  }

  async updatePosition(itemId, newPosition) {
    const url = this.updateUrlValue.replace(':id', itemId)
    
    const response = await fetch(url, {
      method: 'PATCH',
      headers: this.getRequestHeaders(),
      body: JSON.stringify({
        position: newPosition
      })
    })

    if (!response.ok) {
      throw new Error(`HTTP ${response.status}: ${response.statusText}`)
    }

    return await response.json()
  }

  revertSortChange(event) {
    // Move the item back to its original position
    const container = event.to
    const item = event.item
    const oldIndex = event.oldIndex
    
    // Remove item from current position
    item.remove()
    
    // Insert at old position
    const children = Array.from(container.children)
    if (oldIndex >= children.length) {
      container.appendChild(item)
    } else {
      container.insertBefore(item, children[oldIndex])
    }
  }

  getRequestHeaders() {
    const token = document.querySelector('meta[name="csrf-token"]')
    return {
      'Content-Type': 'application/json',
      'X-CSRF-Token': token ? token.getAttribute('content') : '',
      'X-Requested-With': 'XMLHttpRequest'
    }
  }

  initializeArrowButtons() {
    // Always remove existing event listener first to prevent duplicates
    if (this.arrowClickHandler) {
      this.element.removeEventListener('click', this.arrowClickHandler)
    }
    
    // Create bound handler and store reference for cleanup
    this.arrowClickHandler = this.handleArrowClick.bind(this)
    this.element.addEventListener('click', this.arrowClickHandler)
  }

  async handleArrowClick(event) {
    // Try multiple ways to find the arrow button
    let arrowButton = event.target.closest('.position-arrow')
    if (!arrowButton) {
      arrowButton = event.target.closest('button[data-action]')
    }
    if (!arrowButton && event.target.tagName === 'BUTTON') {
      arrowButton = event.target
    }
    
    if (!arrowButton) {
      return
    }
    
    if (arrowButton.classList.contains('disabled')) {
      return
    }

    event.preventDefault()
    event.stopPropagation()

    const itemId = arrowButton.dataset.itemId
    const action = arrowButton.dataset.action
    
    if (!itemId || !action) {
      console.error('Missing item ID or action on arrow button')
      return
    }

    // Use a more robust deduplication key
    const requestKey = `${itemId}-${action}`
    
    // Check for existing request globally (across all controller instances)
    if (window.activeArrowRequests && window.activeArrowRequests.has(requestKey)) {
      return
    }
    
    // Initialize global request tracker if it doesn't exist
    if (!window.activeArrowRequests) {
      window.activeArrowRequests = new Set()
    }
    
    // Mark this request as active
    window.activeArrowRequests.add(requestKey)

    try {
      arrowButton.style.opacity = '0.5'
      arrowButton.style.pointerEvents = 'none'

      const response = await this.moveItem(itemId, action)
      
      if (response.status === 'success') {
        this.showNotification(response.message, 'success')
        // Refresh the page content to reflect new positions
        await this.refreshPositions()
      } else {
        throw new Error(response.message || `Failed to ${action.replace('_', ' ')}`)
      }
    } catch (error) {
      this.showNotification(error.message || `Failed to ${action.replace('_', ' ')}`, 'error')
    } finally {
      arrowButton.style.opacity = ''
      arrowButton.style.pointerEvents = ''
      
      // Remove from global request tracker
      if (window.activeArrowRequests) {
        window.activeArrowRequests.delete(requestKey)
      }
    }
  }

  async moveItem(itemId, action) {
    const baseUrl = this.updateUrlValue.replace('/update_position', '').replace(':id', itemId)
    const url = `${baseUrl}/${action}`
    
    const response = await fetch(url, {
      method: 'PATCH',
      headers: this.getRequestHeaders()
    })

    if (!response.ok) {
      throw new Error(`HTTP ${response.status}: ${response.statusText}`)
    }

    return await response.json()
  }

  async refreshPositions() {
    // Prevent multiple refresh calls
    if (this.isRefreshing) {
      return
    }
    
    this.isRefreshing = true
    
    try {
      const response = await fetch(window.location.href, {
        headers: {
          'Accept': 'text/html',
          'X-Requested-With': 'XMLHttpRequest'
        }
      })
      
      if (response.ok) {
        const html = await response.text()
        const parser = new DOMParser()
        const doc = parser.parseFromString(html, 'text/html')
        
        // Find the container that holds our sortable items
        const newContent = doc.querySelector('[data-controller*="sortable"]')
        if (newContent) {
          // Clear sortable initialization flag
          this.element.removeAttribute('data-sortable-initialized')
          
          // Destroy existing sortable instances
          if (this.sortable) {
            this.sortable.destroy()
            this.sortable = null
          }
          if (this.sortables) {
            this.sortables.forEach(sortable => sortable.destroy())
            this.sortables = null
          }
          
          // Replace the current content with updated content
          this.element.innerHTML = newContent.innerHTML
          
          // Reinitialize everything fresh
          this.initializeSortable()
          this.initializeArrowButtons()
        }
      }
    } catch (error) {
      // Fallback to page reload if AJAX refresh fails
      window.location.reload()
    } finally {
      this.isRefreshing = false
    }
  }

  showNotification(message, type = 'info') {
    // Create a simple notification
    const notification = document.createElement('div')
    notification.className = `notification notification-${type} fixed top-4 right-4 z-50 px-6 py-3 rounded-lg shadow-lg`
    notification.style.cssText = `
      background-color: ${type === 'success' ? '#10b981' : type === 'error' ? '#ef4444' : '#3b82f6'};
      color: white;
      font-weight: 500;
      transform: translateX(100%);
      transition: transform 0.3s ease-in-out;
    `
    notification.textContent = message
    
    document.body.appendChild(notification)
    
    // Slide in
    setTimeout(() => {
      notification.style.transform = 'translateX(0)'
    }, 10)
    
    // Auto-remove after 3 seconds
    setTimeout(() => {
      notification.style.transform = 'translateX(100%)'
      setTimeout(() => {
        notification.remove()
      }, 300)
    }, 3000)
  }
} 