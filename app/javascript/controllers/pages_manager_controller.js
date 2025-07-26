import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

export default class extends Controller {
  static targets = ["pageGrid", "bulkActions", "selectAll", "pageCheckbox", "sortSelect"]
  static values = { 
    updatePriorityUrl: String,
    bulkActionUrl: String
  }

  connect() {
    this.initializeSortable()
    this.initializeBulkActions()
    this.updateBulkActionsVisibility()
  }

  initializeSortable() {
    if (this.hasPageGridTarget) {
      this.sortable = Sortable.create(this.pageGridTarget, {
        animation: 150,
        ghostClass: "opacity-50",
        onEnd: (evt) => {
          this.updatePageOrder()
        }
      })
    }
  }

  initializeBulkActions() {
    // Show/hide bulk actions based on selection
    this.pageCheckboxTargets.forEach(checkbox => {
      checkbox.addEventListener('change', () => {
        this.updateBulkActionsVisibility()
      })
    })
  }

  selectAllChanged() {
    const isChecked = this.selectAllTarget.checked
    this.pageCheckboxTargets.forEach(checkbox => {
      checkbox.checked = isChecked
    })
    this.updateBulkActionsVisibility()
  }

  pageCheckboxChanged() {
    this.updateBulkActionsVisibility()
    
    // Update select all checkbox state
    const totalCheckboxes = this.pageCheckboxTargets.length
    const checkedCheckboxes = this.getSelectedPageIds().length
    
    this.selectAllTarget.checked = checkedCheckboxes === totalCheckboxes
    this.selectAllTarget.indeterminate = checkedCheckboxes > 0 && checkedCheckboxes < totalCheckboxes
  }

  updateBulkActionsVisibility() {
    const selectedCount = this.getSelectedPageIds().length
    
    if (this.hasBulkActionsTarget) {
      if (selectedCount > 0) {
        this.bulkActionsTarget.classList.remove('hidden')
        this.updateBulkActionText(selectedCount)
      } else {
        this.bulkActionsTarget.classList.add('hidden')
      }
    }
  }

  updateBulkActionText(count) {
    const text = this.bulkActionsTarget.querySelector('[data-selected-count]')
    if (text) {
      text.textContent = `${count} selected`
    }
  }

  getSelectedPageIds() {
    return this.pageCheckboxTargets
      .filter(checkbox => checkbox.checked)
      .map(checkbox => checkbox.value)
  }

  async performBulkAction(event) {
    const action = event.currentTarget.dataset.action
    const selectedIds = this.getSelectedPageIds()
    
    if (selectedIds.length === 0) {
      alert('Please select at least one page')
      return
    }

    // Confirm destructive actions
    if (action === 'delete') {
      if (!confirm(`Are you sure you want to delete ${selectedIds.length} page(s)? This cannot be undone.`)) {
        return
      }
    }

    try {
      const response = await fetch(this.bulkActionUrlValue, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
        },
        body: JSON.stringify({
          page_ids: selectedIds,
          bulk_action: action
        })
      })

      if (response.ok) {
        window.location.reload()
      } else {
        throw new Error('Bulk action failed')
      }
    } catch (error) {
      console.error('Bulk action error:', error)
      alert('Failed to perform bulk action. Please try again.')
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

  // Keyboard shortcuts
  handleKeyDown(event) {
    if (event.target.tagName === 'INPUT' || event.target.tagName === 'TEXTAREA') return
    
    switch(event.key) {
      case 'Delete':
      case 'Backspace':
        if (this.getSelectedPageIds().length > 0) {
          event.preventDefault()
          this.performBulkAction({ currentTarget: { dataset: { action: 'delete' } } })
        }
        break
      case 'a':
        if (event.ctrlKey || event.metaKey) {
          event.preventDefault()
          this.selectAllTarget.checked = true
          this.selectAllChanged()
        }
        break
      case 'Escape':
        this.selectAllTarget.checked = false
        this.selectAllChanged()
        this.closeMenus({ target: document.body })
        break
    }
  }
}