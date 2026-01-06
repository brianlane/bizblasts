import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="section-gallery-manager"
export default class extends Controller {
  static targets = ["modal", "photosTab", "videoTab", "photoGrid", "photoInput",
                    "videoInput", "videoTitle", "videoAutoplay", "photoCount"]
  static values = {
    sectionId: String,
    pageId: String
  }

  connect() {
    // Controller connected and ready
  }

  // Open the modal
  openModal(event) {
    event.preventDefault()
    const modal = document.getElementById('gallery-manager-modal')
    if (modal) {
      modal.classList.remove('hidden')
      document.body.style.overflow = 'hidden'
    }
  }

  // Close the modal
  closeModal() {
    const modal = document.getElementById('gallery-manager-modal')
    if (modal) {
      modal.classList.add('hidden')
      document.body.style.overflow = 'auto'
    }
  }

  // Switch between tabs
  switchTab(event) {
    const tab = event.currentTarget.dataset.tab

    // Update tab button styles
    document.querySelectorAll('.tab-button').forEach(button => {
      button.classList.remove('border-blue-500', 'text-blue-600')
      button.classList.add('border-transparent', 'text-gray-500')
    })
    event.currentTarget.classList.remove('border-transparent', 'text-gray-500')
    event.currentTarget.classList.add('border-blue-500', 'text-blue-600')

    // Show/hide tab content
    if (tab === 'photos') {
      this.photosTabTarget.classList.remove('hidden')
      this.videoTabTarget.classList.add('hidden')
    } else if (tab === 'video') {
      this.photosTabTarget.classList.add('hidden')
      this.videoTabTarget.classList.remove('hidden')
    }
  }

  // Trigger photo file input
  triggerPhotoUpload() {
    this.photoInputTarget.click()
  }

  // Upload photos
  async uploadPhotos(event) {
    const files = event.target.files
    if (!files || files.length === 0) return

    // Show upload progress
    this.showNotification('Uploading photos...', 'info')

    for (const file of files) {
      await this.uploadSinglePhoto(file)
    }

    // Clear the file input
    event.target.value = ''

    // Reload the page to show new photos
    this.showNotification('Photos uploaded successfully!', 'success')
    setTimeout(() => window.location.reload(), 1000)
  }

  // Upload a single photo
  async uploadSinglePhoto(file) {
    const formData = new FormData()
    formData.append('photo', file)

    const url = `/manage/website/pages/${this.pageIdValue}/sections/${this.sectionIdValue}/gallery/upload_photo`

    try {
      const response = await fetch(url, {
        method: 'POST',
        headers: {
          'X-CSRF-Token': this.getCSRFToken()
        },
        body: formData
      })

      const data = await response.json()

      if (data.status !== 'success') {
        throw new Error(data.error || 'Upload failed')
      }

      return data.photo
    } catch (error) {
      console.error('Error uploading photo:', error)
      this.showNotification(`Error uploading photo: ${error.message}`, 'error')
      throw error
    }
  }

  // Delete a photo
  async deletePhoto(event) {
    if (!confirm('Are you sure you want to delete this photo?')) return

    const photoId = event.currentTarget.dataset.photoId
    const url = `/manage/website/pages/${this.pageIdValue}/sections/${this.sectionIdValue}/gallery/photos/${photoId}`

    try {
      const response = await fetch(url, {
        method: 'DELETE',
        headers: {
          'X-CSRF-Token': this.getCSRFToken(),
          'Content-Type': 'application/json'
        }
      })

      const data = await response.json()

      if (data.status === 'success') {
        this.showNotification('Photo deleted successfully!', 'success')
        setTimeout(() => window.location.reload(), 500)
      } else {
        throw new Error('Delete failed')
      }
    } catch (error) {
      console.error('Error deleting photo:', error)
      this.showNotification('Error deleting photo', 'error')
    }
  }

  // Trigger video file input
  triggerVideoUpload() {
    this.videoInputTarget.click()
  }

  // Upload video
  async uploadVideo(event) {
    const file = event.target.files[0]
    if (!file) return

    // Check file size (50MB max)
    if (file.size > 50 * 1024 * 1024) {
      this.showNotification('Video file must be less than 50MB', 'error')
      return
    }

    this.showNotification('Uploading video...', 'info')

    const formData = new FormData()
    formData.append('video', file)
    formData.append('video_title', this.videoTitleTarget.value)
    formData.append('video_autoplay', this.videoAutoplayTarget.checked)

    const url = `/manage/website/pages/${this.pageIdValue}/sections/${this.sectionIdValue}/gallery/upload_video`

    try {
      const response = await fetch(url, {
        method: 'POST',
        headers: {
          'X-CSRF-Token': this.getCSRFToken()
        },
        body: formData
      })

      const data = await response.json()

      if (data.status === 'success') {
        this.showNotification('Video uploaded successfully!', 'success')
        setTimeout(() => window.location.reload(), 1000)
      } else {
        throw new Error('Upload failed')
      }
    } catch (error) {
      console.error('Error uploading video:', error)
      this.showNotification('Error uploading video', 'error')
    }
  }

  // Remove video
  async removeVideo(event) {
    if (!confirm('Are you sure you want to remove this video?')) return

    const url = `/manage/website/pages/${this.pageIdValue}/sections/${this.sectionIdValue}/gallery/remove_video`

    try {
      const response = await fetch(url, {
        method: 'DELETE',
        headers: {
          'X-CSRF-Token': this.getCSRFToken(),
          'Content-Type': 'application/json'
        }
      })

      const data = await response.json()

      if (data.status === 'success') {
        this.showNotification('Video removed successfully!', 'success')
        setTimeout(() => window.location.reload(), 500)
      } else {
        throw new Error('Remove failed')
      }
    } catch (error) {
      console.error('Error removing video:', error)
      this.showNotification('Error removing video', 'error')
    }
  }

  // Helper: Get CSRF token
  getCSRFToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content
  }

  // Helper: Show notification
  showNotification(message, type = 'info') {
    // Create a simple toast notification
    const toast = document.createElement('div')
    toast.className = `fixed top-4 right-4 px-6 py-3 rounded-lg shadow-lg z-50 ${
      type === 'success' ? 'bg-green-500' :
      type === 'error' ? 'bg-red-500' :
      'bg-blue-500'
    } text-white`
    toast.textContent = message

    document.body.appendChild(toast)

    setTimeout(() => {
      toast.remove()
    }, 3000)
  }
}
