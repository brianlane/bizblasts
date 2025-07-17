/**
 * Page Editor Controller - Website Builder Section Management
 * 
 * This Stimulus controller manages the website builder interface for adding,
 * editing, and reordering page sections. It supports both drag-and-drop
 * functionality and button click interactions.
 * 
 * Key Features:
 * - Unified section creation (addNewSection) that handles both drag-and-drop and button clicks
 * - Alternative addSection method for backwards compatibility
 * - CSRF token handling (gracefully handles test environments where CSRF is disabled)
 * - Duplicate request prevention
 * - Real-time DOM updates via refreshSections
 * - User feedback via notifications
 * - Comprehensive error handling
 * 
 * Usage:
 * 1. Drag-and-drop: Sections can be dragged from the library and dropped in the builder
 * 2. Button clicks: "Add Section" buttons trigger immediate section creation
 * 3. Section management: Edit, delete, and reorder existing sections
 * 
 * Methods:
 * - addNewSection(sectionTypeOrEvent, position): Unified method for both interaction types
 * - addSection(event): Alternative method specifically for button clicks
 * - createSection(sectionType, position): Core section creation logic
 * - refreshSections(): Updates the DOM with latest section data
 * - All drag-and-drop handlers for reordering
 */

import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

export default class extends Controller {
  static targets = ["sectionsContainer", "addSectionForm", "versionSelector", "previewFrame", "previewOverlay", "previewToggleText", "editModal", "editModalContent"]
  static values = { 
    pageId: String,
    availableSections: Array,
    reorderUrl: String
  }

  connect() {
    this.initializeSortable()
    this.initializeAutoSave()
    this.previewMode = false
    this.setupDragAndDrop()
    this.lastAddRequest = null // Initialize duplicate request tracking
    //console.log("Page editor connected for page:", this.pageIdValue)
    //console.log("Available targets:", Object.keys(this.targets))
    //console.log("Sections container:", this.hasSectionsContainerTarget ? "✓" : "✗")
  }

  disconnect() {
    if (this.sortable) {
      this.sortable.destroy()
    }
    if (this.autoSaveInterval) {
      clearInterval(this.autoSaveInterval)
    }
  }

  initializeSortable() {
    if (this.hasSectionsContainerTarget) {
      this.sortable = Sortable.create(this.sectionsContainerTarget, {
        animation: 150,
        ghostClass: 'section-ghost',
        chosenClass: 'section-chosen',
        dragClass: 'section-drag',
        filter: '.section-library-item', // Exclude library items from sortable
        onEnd: (evt) => {
          // Only reorder if this was an actual reorder of existing sections
          // Check if the item has a section-id (existing section) vs library item
          const item = evt.item
          if (item && item.dataset.sectionId) {
            this.reorderSections()
          }
        }
      })
    }
  }

  initializeAutoSave() {
    // Auto-save every 30 seconds if there are changes
    this.hasChanges = false
    this.autoSaveInterval = setInterval(() => {
      if (this.hasChanges) {
        this.createVersion()
        this.hasChanges = false
      }
    }, 30000)
  }

  setupDragAndDrop() {
    // Make sections container a drop zone
    this.sectionsContainerTarget.addEventListener('dragover', this.handleDragOver.bind(this))
    this.sectionsContainerTarget.addEventListener('drop', this.handleDrop.bind(this))
  }

  // Handle dragging new sections from the library
  handleDragStart(event) {
    const sectionType = event.target.dataset.sectionType
    event.dataTransfer.setData('text/plain', JSON.stringify({
      type: 'new_section',
      sectionType: sectionType
    }))
    event.dataTransfer.effectAllowed = 'copy'
  }

  // Handle dragging existing sections for reordering
  handleSectionDragStart(event) {
    const sectionId = event.target.dataset.sectionId
    const sectionType = event.target.dataset.sectionType
    
    event.dataTransfer.setData('text/plain', JSON.stringify({
      type: 'existing_section',
      sectionId: sectionId,
      sectionType: sectionType
    }))
    event.dataTransfer.effectAllowed = 'move'
    
    // Add visual feedback
    event.target.classList.add('dragging')
  }

  handleDragOver(event) {
    event.preventDefault()
    event.dataTransfer.dropEffect = 'copy'
    
    // Add visual feedback to drop zone
    this.sectionsContainerTarget.classList.add('drag-over')
  }

  handleDrop(event) {
    event.preventDefault()
    event.stopPropagation()
    this.sectionsContainerTarget.classList.remove('drag-over')
    
    try {
      const data = JSON.parse(event.dataTransfer.getData('text/plain'))
      
      if (data.type === 'new_section') {
        this.addNewSection(data.sectionType, this.calculateDropPosition(event))
      } else if (data.type === 'existing_section') {
        this.reorderSection(data.sectionId, this.calculateDropPosition(event))
      }
    } catch (error) {
      console.error('Error handling drop:', error)
    }
    
    // Clean up drag visual feedback
    document.querySelectorAll('.dragging').forEach(el => {
      el.classList.remove('dragging')
    })
  }

  calculateDropPosition(event) {
    const container = this.sectionsContainerTarget
    const sections = Array.from(container.querySelectorAll('.section-item'))
    const y = event.clientY
    
    for (let i = 0; i < sections.length; i++) {
      const rect = sections[i].getBoundingClientRect()
      if (y < rect.top + rect.height / 2) {
        return i
      }
    }
    return sections.length
  }

  /**
   * Add New Section - Unified method for both drag-and-drop and button clicks
   * Can be called directly with section type and position, or as an event handler
   */
  async addNewSection(sectionTypeOrEvent, position = null) {
    //console.log('=== addNewSection called ===')
    
    let sectionType, eventFromButton = false
    
    // Handle both direct calls and event-based calls
    if (typeof sectionTypeOrEvent === 'object' && sectionTypeOrEvent.target) {
      // This is an event from button click
      const event = sectionTypeOrEvent
      event.preventDefault()
      event.stopPropagation()
      
      sectionType = event.currentTarget.dataset.sectionType
      position = null // Button clicks add to the end
      eventFromButton = true
      //console.log('Event-based call detected, section type:', sectionType)
    } else {
      // Direct call with section type
      sectionType = sectionTypeOrEvent
      //console.log('Direct call, section type:', sectionType, 'position:', position)
    }
    
    // Validate section type
    if (!sectionType) {
      console.error('No section type provided')
      this.showNotification('Error: No section type specified', 'error')
      return
    }
    
    // Calculate position if not provided (button clicks or end-of-list drops)
    if (position === null) {
      const existingSections = this.sectionsContainerTarget.querySelectorAll('.section-item')
      position = existingSections.length
      //console.log('Calculated position:', position)
    }
    
    return this.createSection(sectionType, position)
  }

  /**
   * Add Section - Alternative method specifically for button clicks
   * This maintains backwards compatibility
   */
  async addSection(event) {
    //console.log('=== addSection called ===')
    return this.addNewSection(event)
  }

  /**
   * Core section creation method
   * Handles the actual AJAX request and DOM updates
   */
  async createSection(sectionType, position) {
    // Prevent duplicate calls
    const requestKey = `add-${sectionType}-${position}-${Date.now()}`
    
    if (this.lastAddRequest && (Date.now() - this.lastAddRequest.time) < 1000) {
      //console.log('Duplicate request blocked')
      return
    }
    
    this.lastAddRequest = { key: requestKey, time: Date.now() }
    
    try {
      //console.log('Creating section:', sectionType, 'at position:', position)
      
      const requestBody = {
        page_section: {
          section_type: sectionType,
          position: position,
          content: this.getDefaultContent(sectionType)
        }
      }
      
      //console.log('Request body:', requestBody)
      //console.log('Making request to:', `/manage/website/pages/${this.pageIdValue}/sections`)
      
      const response = await fetch(`/manage/website/pages/${this.pageIdValue}/sections`, {
        method: 'POST',
        headers: this.getRequestHeaders(),
        body: JSON.stringify(requestBody)
      })

      //console.log('Response status:', response.status, 'ok:', response.ok)

      if (response.ok) {
        const result = await response.json()
        //console.log('Section created successfully:', result)
        
        // Refresh the sections display
        await this.refreshSections()
        
        // Show success notification
        const sectionName = sectionType.replace('_', ' ').replace(/\b\w/g, l => l.toUpperCase())
        this.showNotification(`${sectionName} section added successfully`, 'success')
        
        return result
      } else {
        const errorText = await response.text()
        console.error('Server response error:', response.status, errorText)
        throw new Error(`Server error: ${response.status}`)
      }
    } catch (error) {
      console.error('Error creating section:', error)
      this.showNotification('Failed to add section: ' + error.message, 'error')
      throw error
    }
  }

  async reorderSection(sectionId, newPosition) {
    try {
      const response = await fetch(`/manage/website/pages/${this.pageIdValue}/sections/${sectionId}/reorder`, {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
        },
        body: JSON.stringify({
          position: newPosition
        })
      })

      if (response.ok) {
        this.refreshSections()
        this.showNotification('Section reordered successfully', 'success')
      } else {
        throw new Error('Failed to reorder section')
      }
    } catch (error) {
      console.error('Error reordering section:', error)
      this.showNotification('Failed to reorder section', 'error')
    }
  }

  async deleteSection(event) {
    const sectionId = event.target.dataset.sectionId
    
    if (!confirm('Are you sure you want to delete this section? This cannot be undone.')) {
      return
    }

    try {
      const response = await fetch(`/manage/website/pages/${this.pageIdValue}/sections/${sectionId}`, {
        method: 'DELETE',
        headers: {
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
        }
      })

      if (response.ok) {
        this.refreshSections()
        this.showNotification('Section deleted successfully', 'success')
      } else {
        throw new Error('Failed to delete section')
      }
    } catch (error) {
      console.error('Error deleting section:', error)
      this.showNotification('Failed to delete section', 'error')
    }
  }

  async editSection(event) {
    const sectionId = event.target.dataset.sectionId
    
    try {
      const response = await fetch(`/manage/website/pages/${this.pageIdValue}/sections/${sectionId}/edit`, {
        headers: {
          'Accept': 'text/html'
        }
      })

      if (response.ok) {
        const html = await response.text()
        this.editModalContentTarget.innerHTML = html
        this.editModalTarget.classList.remove('hidden')
      } else {
        throw new Error('Failed to load section editor')
      }
    } catch (error) {
      console.error('Error loading section editor:', error)
      this.showNotification('Failed to load section editor', 'error')
    }
  }

  closeEditModal() {
    this.editModalTarget.classList.add('hidden')
    this.editModalContentTarget.innerHTML = ''
  }

  togglePreview() {
    if (this.previewOverlayTarget.classList.contains('hidden')) {
      // Show preview
      const previewUrl = `/manage/website/pages/${this.pageIdValue}/preview`
      this.previewFrameTarget.src = previewUrl
      this.previewOverlayTarget.classList.remove('hidden')
      this.previewToggleTextTarget.textContent = 'Hide Preview'
    } else {
      // Hide preview
      this.previewOverlayTarget.classList.add('hidden')
      this.previewFrameTarget.src = ''
      this.previewToggleTextTarget.textContent = 'Show Preview'
    }
  }

  async refreshSections() {
    //console.log('=== refreshSections called ===')
    try {
      const response = await fetch(`/manage/website/pages/${this.pageIdValue}/sections`, {
        headers: {
          'Accept': 'text/html'
        }
      })

      //console.log('Refresh sections response status:', response.status)
      //console.log('Refresh sections response ok:', response.ok)

      if (response.ok) {
        const html = await response.text()
        //console.log('Received HTML length:', html.length)
        
        // Extract just the sections container content
        const parser = new DOMParser()
        const doc = parser.parseFromString(html, 'text/html')
        const newContainer = doc.querySelector('#page-sections-container')
        
        //console.log('New container found:', !!newContainer)
        if (newContainer) {
          //console.log('New container innerHTML length:', newContainer.innerHTML.length)
          //console.log('Current container target:', this.sectionsContainerTarget)
          this.sectionsContainerTarget.innerHTML = newContainer.innerHTML
          //console.log('DOM updated successfully')
          
          // Check if we now have section items
          const sectionItems = this.sectionsContainerTarget.querySelectorAll('.section-item')
          //console.log('Section items after refresh:', sectionItems.length)
        } else {
          console.error('Could not find #page-sections-container in response')
        }
      } else {
        console.error('Failed to refresh sections:', response.status)
      }
    } catch (error) {
      console.error('Error refreshing sections:', error)
    }
  }

  removeSection(event) {
    event.preventDefault()
    const sectionId = event.currentTarget.dataset.sectionId
    
    if (!confirm('Are you sure you want to remove this section?')) {
      return
    }

    fetch(`/manage/website/pages/${this.pageIdValue}/sections/${sectionId}`, {
      method: 'DELETE',
      headers: {
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
        'Accept': 'application/json'
      }
    })
    .then(response => response.json())
    .then(data => {
      if (data.status === 'success') {
        this.refreshSections()
        this.showNotification('Section removed successfully', 'success')
      } else {
        this.showNotification('Failed to remove section', 'error')
      }
    })
  }

  duplicateSection(event) {
    event.preventDefault()
    const sectionId = event.currentTarget.dataset.sectionId

    fetch(`/manage/website/pages/${this.pageIdValue}/sections/${sectionId}/duplicate`, {
      method: 'POST',
      headers: {
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
        'Accept': 'application/json'
      }
    })
    .then(response => response.json())
    .then(data => {
      if (data.status === 'success') {
        this.refreshSections()
        this.showNotification('Section duplicated successfully', 'success')
      } else {
        this.showNotification('Failed to duplicate section', 'error')
      }
    })
  }

  reorderSections() {
    const sectionIds = Array.from(this.sectionsContainerTarget.children)
      .map(section => section.dataset.sectionId)
      .filter(id => id)

    //console.log('Reordering sections:', sectionIds)

    // Don't send empty reorder requests
    if (sectionIds.length === 0) {
      //console.log('No sections to reorder, skipping')
      return
    }

    fetch(`/manage/website/pages/${this.pageIdValue}/sections/reorder`, {
      method: 'PATCH',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
        'Accept': 'application/json'
      },
      body: JSON.stringify({ section_ids: sectionIds })
    })
    .then(response => response.json())
    .then(data => {
      if (data.status === 'success') {
        this.refreshSections()
        this.showNotification('Sections reordered successfully', 'success')
      } else {
        this.showNotification('Failed to reorder sections', 'error')
      }
    })
    .catch(error => {
      console.error('Error reordering sections:', error)
      this.showNotification('Failed to reorder sections', 'error')
    })
  }

  // Version Management
  createVersion(event = null) {
    if (event) {
      event.preventDefault()
    }

    const notes = event ? prompt('Version notes (optional):') : 'Auto-save'
    
    fetch(`/manage/website/pages/${this.pageIdValue}/create_version`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
        'Accept': 'application/json'
      },
      body: JSON.stringify({ notes: notes })
    })
    .then(response => response.json())
    .then(data => {
      if (data.status === 'success') {
        this.updateVersionSelector()
        if (event) {
          this.showNotification(`Version ${data.version} created`, 'success')
        }
      }
    })
  }

  restoreVersion(event) {
    event.preventDefault()
    const versionId = this.versionSelectorTarget.value
    
    if (!versionId || !confirm('Are you sure you want to restore this version? Current changes will be lost.')) {
      return
    }

    fetch(`/manage/website/pages/${this.pageIdValue}/restore_version`, {
      method: 'PATCH',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
      },
      body: JSON.stringify({ version_id: versionId })
    })
    .then(() => {
      window.location.reload()
    })
  }

  // Publishing
  publishPage(event) {
    event.preventDefault()
    
    if (!confirm('Are you sure you want to publish this page? It will be visible to visitors.')) {
      return
    }

    fetch(`/manage/website/pages/${this.pageIdValue}/publish`, {
      method: 'PATCH',
      headers: {
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
      }
    })
    .then(() => {
      window.location.reload()
    })
  }

  // Utility Methods
  updateVersionSelector() {
    if (this.hasVersionSelectorTarget) {
      fetch(`/manage/website/pages/${this.pageIdValue}`)
        .then(response => response.text())
        .then(html => {
          const parser = new DOMParser()
          const doc = parser.parseFromString(html, 'text/html')
          const newSelector = doc.querySelector('[data-page-editor-target="versionSelector"]')
          
          if (newSelector) {
            this.versionSelectorTarget.innerHTML = newSelector.innerHTML
          }
        })
    }
  }

  // Helper method to safely get CSRF token (handles test environment where it's disabled)
  getCsrfToken() {
    const csrfElement = document.querySelector('[name="csrf-token"]')
    return csrfElement ? csrfElement.content : null
  }

  // Helper method to get headers with optional CSRF token
  getRequestHeaders(extraHeaders = {}) {
    const headers = {
      'Content-Type': 'application/json',
      ...extraHeaders
    }
    
    const csrfToken = this.getCsrfToken()
    if (csrfToken) {
      headers['X-CSRF-Token'] = csrfToken
    }
    
    return headers
  }

  getDefaultContent(sectionType) {
    const defaults = {
      hero_banner: {
        title: 'Welcome to Our Business',
        subtitle: 'We provide excellent services to help you succeed',
        button_text: 'Learn More',
        button_link: '#contact'
      },
      text: {
        content: '<p>Add your content here. You can use rich text formatting to make your content stand out.</p>'
      },
      testimonial: {
        quote: 'This business provided excellent service. I highly recommend them!',
        author: 'Happy Customer',
        company: 'Local Business'
      },
      contact_form: {
        title: 'Get In Touch',
        description: 'Contact us today to learn more about our services.'
      },
      service_list: {
        title: 'Our Services',
        description: 'We offer a wide range of professional services.'
      },
      product_list: {
        title: 'Our Products',
        description: 'Discover our high-quality products designed for your needs.'
      },
      team_showcase: {
        title: 'Meet Our Team',
        description: 'Our experienced professionals are here to help you.'
      },
      gallery: {
        title: 'Gallery',
        description: 'Take a look at our work and facilities.'
      },
      pricing_table: {
        title: 'Our Pricing',
        description: 'Transparent pricing for all our services.'
      },
      faq_section: {
        title: 'Frequently Asked Questions',
        description: 'Find answers to common questions.'
      },
      map_location: {
        title: 'Visit Us',
        description: 'Find us at our convenient location.'
      }
    }

    return defaults[sectionType] || {}
  }

  showNotification(message, type = 'info') {
    // Create a simple notification
    const notification = document.createElement('div')
    notification.className = `fixed top-4 right-4 z-50 px-4 py-2 rounded-lg shadow-lg text-white transition-opacity duration-300 ${
      type === 'success' ? 'bg-green-500' : 
      type === 'error' ? 'bg-red-500' : 
      'bg-blue-500'
    }`
    notification.textContent = message
    
    document.body.appendChild(notification)
    
    // Auto-remove after 3 seconds
    setTimeout(() => {
      notification.style.opacity = '0'
      setTimeout(() => {
        document.body.removeChild(notification)
      }, 300)
    }, 3000)
  }

  markChanged() {
    this.hasChanges = true
  }
} 