import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

export default class extends Controller {
  static targets = ["pageGrid", "sortSelect"]
  static values = { 
    updatePriorityUrl: String
  }

  connect() {
    this.initializeSortable()
  }

  initializeSortable() {
    if (this.hasPageGridTarget) {
      this.sortable = Sortable.create(this.pageGridTarget, {
        animation: 150,
        ghostClass: "opacity-50",
        onEnd: () => {
          this.updatePageOrder()
        }
      })
    }
  }

  async updatePageOrder() {
    const pageCards = this.pageGridTarget.querySelectorAll('[data-page-id]')
    const pageIds = Array.from(pageCards).map(card => card.dataset.pageId)
    
    try {
      const response = await fetch(this.updatePriorityUrlValue, {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
        },
        body: JSON.stringify({
          page_ids: pageIds
        })
      })

      if (response.ok) {
        this.showNotification('Page order updated successfully', 'success')
      } else {
        throw new Error('Failed to update page order')
      }
    } catch (error) {
      console.error('Priority update error:', error)
      this.showNotification('Failed to update page order', 'error')
    }
  }

  sortChanged() {
    const sortValue = this.sortSelectTarget.value
    const url = new URL(window.location)
    url.searchParams.set('sort', sortValue)
    window.location.href = url.toString()
  }

  showNotification(message, type = 'info') {
    // Create a simple toast notification
    const toast = document.createElement('div')
    toast.className = `fixed top-4 right-4 px-6 py-3 rounded-lg text-white z-50 ${
      type === 'success' ? 'bg-green-500' : 
      type === 'error' ? 'bg-red-500' : 'bg-blue-500'
    }`
    toast.textContent = message
    
    document.body.appendChild(toast)
    
    setTimeout(() => {
      toast.remove()
    }, 3000)
  }

  // Enhanced page actions dropdown
  togglePageMenu(event) {
    event.stopPropagation()
    const menu = event.currentTarget.nextElementSibling
    const allMenus = document.querySelectorAll('[data-page-menu]')
    
    // Close all other menus
    allMenus.forEach(m => {
      if (m !== menu) m.classList.add('hidden')
    })
    
    // Toggle current menu
    menu.classList.toggle('hidden')
  }

  // Close menus when clicking outside
  closeMenus(event) {
    if (!event.target.closest('[data-page-menu-trigger]')) {
      document.querySelectorAll('[data-page-menu]').forEach(menu => {
        menu.classList.add('hidden')
      })
    }
  }
}