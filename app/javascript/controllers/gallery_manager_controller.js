import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

// Gallery manager controller for management UI
export default class extends Controller {
  static targets = [
    "editModal",
    "editForm",
    "titleInput",
    "descriptionInput",
    "editErrors",
    "saveButton"
  ]

  connect() {
    this.initializeSortable()
  }

  disconnect() {
    if (this.sortable) {
      this.sortable.destroy()
    }
  }

  handleDropdownChange(event) {
    this.changeView(event)
  }

  initializeSortable() {
    const grid = document.getElementById("gallery_photos_grid")
    if (!grid) return

    // Create sortable instance - always enabled
    this.sortable = Sortable.create(grid, {
      animation: 150,
      handle: '[data-sortable-handle]', // Only allow dragging via handle
      ghostClass: 'sortable-ghost',
      chosenClass: 'sortable-chosen',
      dragClass: 'sortable-drag',
      disabled: false, // Always enabled
      onEnd: this.handleReorder.bind(this)
    })
  }

  async handleReorder(event) {
    // Wait a moment for Sortable to finish DOM manipulation
    await new Promise(resolve => setTimeout(resolve, 100))

    const grid = document.getElementById("gallery_photos_grid")
    if (!grid) {
      console.error("Gallery grid not found")
      return
    }

    // Get all children and filter for actual photo cards
    // Exclude Sortable's temporary ghost/drag elements
    const photoElements = Array.from(grid.children).filter(el => {
      // Must have photo ID and gallery_photo_ id format
      // Must not be a Sortable temporary element
      return el.dataset.photoId && 
             el.id && 
             el.id.startsWith('gallery_photo_') &&
             !el.classList.contains('sortable-ghost')
    })

    const photoIds = photoElements.map(el => el.dataset.photoId).filter(Boolean)
    const uniquePhotoIds = [...new Set(photoIds)]

    if (uniquePhotoIds.length !== photoIds.length) {
      this.showNotification('Error: Duplicate photos detected during reorder', 'error')
      return
    }

    if (uniquePhotoIds.length === 0) {
      return
    }

    try {
      const response = await fetch('/manage/gallery/photos/reorder', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
          'Accept': 'application/json'
        },
        body: JSON.stringify({ photo_ids: uniquePhotoIds })
      })

      if (response.ok) {
        this.showNotification('Photos reordered successfully', 'success')
        // Update position numbers on the cards
        this.updatePositionNumbers()
      } else {
        const errorData = await response.json()
        throw new Error(errorData.error || 'Failed to reorder photos')
      }
    } catch (error) {
      this.showNotification(error.message || 'Failed to reorder photos', 'error')
      // Revert the visual change
      window.location.reload()
    }
  }

  openLinkModal(event) {
    event.preventDefault()
    const modal = document.getElementById("link_images_modal")
    if (modal) {
      modal.classList.remove("hidden")
      document.body.style.overflow = "hidden"
    }
  }

  closeLinkModal() {
    const modal = document.getElementById("link_images_modal")
    if (modal) {
      modal.classList.add("hidden")
      document.body.style.overflow = ""
    }
  }

  changeView(event) {
    // Handle both regular change events and dropdown:selected events
    const view = event.detail?.value || event.target?.value || "grid"
    
    const grid = document.getElementById("gallery_photos_grid")
    if (!grid) return
    
    const photos = grid.querySelectorAll("[data-photo-id]")

    if (view === "list") {
      // Switch to list view
      grid.classList.remove("grid", "grid-cols-2", "md:grid-cols-3", "lg:grid-cols-4", "xl:grid-cols-5", "gap-4")
      grid.classList.add("space-y-3")
      
      // Update each photo card for list view
      photos.forEach(photo => {
        photo.classList.add("!flex", "flex-row", "items-center", "gap-4")
        
        // Find and update image container - it's the first div with bg-gray-200
        const imageWrapper = photo.querySelector(".bg-gray-200")
        if (imageWrapper) {
          imageWrapper.classList.remove("aspect-w-4", "aspect-h-3")
          imageWrapper.classList.add("flex-shrink-0", "w-48")
          
          const img = imageWrapper.querySelector("img")
          if (img) {
            img.classList.remove("w-full", "h-48", "object-cover")
            img.classList.add("w-48", "h-32", "object-cover")
          }
          
          const placeholder = imageWrapper.querySelector(".flex.items-center.justify-center")
          if (placeholder) {
            placeholder.classList.remove("h-48")
            placeholder.classList.add("h-32", "w-48")
          }
        }
        
        const infoContainer = photo.querySelector(".p-3")
        if (infoContainer) {
          infoContainer.classList.add("flex-1", "min-w-0")
        }
      })
    } else {
      // Switch to grid view
      grid.classList.add("grid", "grid-cols-2", "md:grid-cols-3", "lg:grid-cols-4", "xl:grid-cols-5", "gap-4")
      grid.classList.remove("space-y-3")
      
      // Restore each photo card for grid view
      photos.forEach(photo => {
        photo.classList.remove("!flex", "flex-row", "items-center", "gap-4")
        
        const imageWrapper = photo.querySelector(".bg-gray-200")
        if (imageWrapper) {
          imageWrapper.classList.add("aspect-w-4", "aspect-h-3")
          imageWrapper.classList.remove("flex-shrink-0", "w-48")
          
          const img = imageWrapper.querySelector("img")
          if (img) {
            img.classList.add("w-full", "h-48", "object-cover")
            img.classList.remove("w-48", "h-32")
          }
          
          const placeholder = imageWrapper.querySelector(".flex.items-center.justify-center")
          if (placeholder) {
            placeholder.classList.add("h-48")
            placeholder.classList.remove("h-32", "w-48")
          }
        }
        
        const infoContainer = photo.querySelector(".p-3")
        if (infoContainer) {
          infoContainer.classList.remove("flex-1", "min-w-0")
        }
      })
    }
  }

  editPhoto(event) {
    const photoTitle = event.currentTarget.dataset.photoTitle || ""
    const photoDescription = event.currentTarget.dataset.photoDescription || ""
    const updateUrl = event.currentTarget.dataset.photoUpdateUrl

    if (!updateUrl || !this.hasEditFormTarget || !this.hasEditModalTarget) {
      console.error("Edit modal elements missing")
      return
    }

    this.editFormTarget.action = updateUrl
    if (this.hasTitleInputTarget) {
      this.titleInputTarget.value = photoTitle
    }
    if (this.hasDescriptionInputTarget) {
      this.descriptionInputTarget.value = photoDescription
    }

    this.clearErrors()
    this.toggleEditModal(true)

    if (this.hasTitleInputTarget) {
      this.titleInputTarget.focus()
    }
  }

  async submitEdit(event) {
    event.preventDefault()
    if (!this.hasEditFormTarget) return

    this.clearErrors()
    this.setSaving(true)

    try {
      const formData = new FormData(this.editFormTarget)
      const response = await fetch(this.editFormTarget.action, {
        method: "POST",
        headers: {
          Accept: "application/json",
          "X-CSRF-Token": document.querySelector('[name="csrf-token"]').content
        },
        body: formData
      })

      if (response.ok) {
        const data = await response.json().catch(() => ({}))
        this.toggleEditModal(false)
        this.showNotification("Photo updated successfully", "success")
        if (data?.id) {
          this.updatePhotoCard(data)
        } else {
          window.location.reload()
        }
      } else {
        const data = await response.json().catch(() => ({}))
        this.showErrors(data.errors || data.error || "Failed to update photo")
      }
    } catch (error) {
      console.error("Update photo error", error)
      this.showErrors("Failed to update photo")
    } finally {
      this.setSaving(false)
    }
  }

  toggleEditModal(show) {
    if (!this.hasEditModalTarget) return

    this.editModalTarget.classList.toggle("hidden", !show)
    document.body.style.overflow = show ? "hidden" : ""
  }

  closeEditModal(event) {
    if (event) event.stopPropagation()
    this.toggleEditModal(false)
  }

  stopPropagation(event) {
    event.stopPropagation()
  }

  clearErrors() {
    if (!this.hasEditErrorsTarget) return
    this.editErrorsTarget.classList.add("hidden")
    this.editErrorsTarget.textContent = ""
  }

  showErrors(errors) {
    if (!this.hasEditErrorsTarget) return
    let message = errors
    if (Array.isArray(errors)) {
      message = errors.join(", ")
    } else if (errors && typeof errors === "object") {
      message = Object.values(errors).flat().join(", ")
    }
    this.editErrorsTarget.textContent = message
    this.editErrorsTarget.classList.remove("hidden")
  }

  setSaving(isSaving) {
    if (!this.hasSaveButtonTarget) return
    this.saveButtonTarget.disabled = isSaving
    this.saveButtonTarget.textContent = isSaving ? "Saving..." : "Save Changes"
  }

  updatePhotoCard(photo) {
    const card = document.getElementById(`gallery_photo_${photo.id}`)
    if (!card) return

    // Update stored data attributes for future edits
    card.dataset.photoTitle = photo.title || ""
    card.dataset.photoDescription = photo.description || ""
    const editButton = card.querySelector('[data-action~="gallery-manager#editPhoto"]')
    if (editButton) {
      editButton.dataset.photoTitle = photo.title || ""
      editButton.dataset.photoDescription = photo.description || ""
    }

    const titleEl = card.querySelector('[data-photo-field="title"]')
    if (titleEl) {
      if (photo.title && photo.title.length > 0) {
        titleEl.textContent = photo.title
        titleEl.classList.remove("text-gray-400", "italic")
        titleEl.classList.add("text-gray-900")
      } else {
        titleEl.textContent = "No title"
        titleEl.classList.add("text-gray-400", "italic")
        titleEl.classList.remove("text-gray-900")
      }
    }

    const descriptionEl = card.querySelector('[data-photo-field="description"]')
    const infoContainer = card.querySelector(".p-3")

    if (photo.description && photo.description.length > 0) {
      if (descriptionEl) {
        descriptionEl.textContent = photo.description
      } else if (infoContainer) {
        const newDescription = document.createElement("p")
        newDescription.dataset.photoField = "description"
        newDescription.className = "mt-1 text-xs text-gray-500 line-clamp-2"
        newDescription.textContent = photo.description
        const statusRow = infoContainer.querySelector(".mt-2.flex.items-center.justify-between.text-xs.text-gray-500")
        infoContainer.insertBefore(newDescription, statusRow)
      }
    } else if (descriptionEl) {
      descriptionEl.remove()
    }

  }

  updatePositionNumbers() {
    const grid = document.getElementById("gallery_photos_grid")
    if (!grid) return

    // Get all photo cards in their current DOM order
    const photoCards = Array.from(grid.children).filter(el => {
      return el.id && el.id.startsWith('gallery_photo_')
    })

    // Update each card's position number
    photoCards.forEach((card, index) => {
      const positionSpan = card.querySelector('[data-photo-field="position"]')
      if (positionSpan) {
        positionSpan.textContent = `Position: ${index + 1}`
      }
    })
  }

  showNotification(message, type = 'info') {
    const notification = document.createElement('div')
    notification.className = 'fixed top-4 right-4 z-50 px-6 py-3 rounded-lg shadow-lg'
    notification.style.cssText = `
      background-color: ${type === 'success' ? '#10b981' : type === 'error' ? '#ef4444' : '#3b82f6'};
      color: white;
      font-weight: 500;
      transform: translateX(100%);
      transition: transform 0.3s ease-in-out;
    `
    notification.textContent = message
    
    document.body.appendChild(notification)
    
    setTimeout(() => notification.style.transform = 'translateX(0)', 10)
    setTimeout(() => {
      notification.style.transform = 'translateX(100%)'
      setTimeout(() => notification.remove(), 300)
    }, 3000)
  }
}
