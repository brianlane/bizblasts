import { Controller } from "@hotwired/stimulus"

// Controls the job attachments manager for uploading files
export default class extends Controller {
  static targets = ["dropzone", "form", "existingList"]
  static values = {
    attachableType: String,
    attachableId: Number
  }

  connect() {
    this.setupDropzone()
  }

  setupDropzone() {
    if (!this.hasDropzoneTarget) return

    const dropzone = this.dropzoneTarget

    // Prevent default drag behaviors
    ;['dragenter', 'dragover', 'dragleave', 'drop'].forEach(eventName => {
      dropzone.addEventListener(eventName, this.preventDefaults.bind(this), false)
      document.body.addEventListener(eventName, this.preventDefaults.bind(this), false)
    })

    // Highlight drop area when file is dragged over
    ;['dragenter', 'dragover'].forEach(eventName => {
      dropzone.addEventListener(eventName, this.highlight.bind(this), false)
    })

    ;['dragleave', 'drop'].forEach(eventName => {
      dropzone.addEventListener(eventName, this.unhighlight.bind(this), false)
    })

    // Handle dropped files
    dropzone.addEventListener('drop', this.handleDrop.bind(this), false)
  }

  preventDefaults(e) {
    e.preventDefault()
    e.stopPropagation()
  }

  highlight() {
    this.dropzoneTarget.classList.add('border-blue-500', 'bg-blue-50', 'dark:bg-blue-900')
    this.dropzoneTarget.classList.remove('border-gray-300', 'dark:border-gray-600')
  }

  unhighlight() {
    this.dropzoneTarget.classList.remove('border-blue-500', 'bg-blue-50', 'dark:bg-blue-900')
    this.dropzoneTarget.classList.add('border-gray-300', 'dark:border-gray-600')
  }

  handleDrop(e) {
    const dt = e.dataTransfer
    const files = dt.files

    if (files.length > 0) {
      this.uploadFiles(files)
    }
  }

  async uploadFiles(files) {
    for (const file of files) {
      await this.uploadFile(file)
    }
  }

  async uploadFile(file) {
    const formData = new FormData()
    formData.append('file', file)
    formData.append('attachment_type', this.determineAttachmentType(file))
    formData.append('visibility', 'internal')
    formData.append('title', file.name.replace(/\.[^/.]+$/, '')) // Remove extension for title

    // Get CSRF token
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

    try {
      // Show uploading indicator
      this.showUploadingIndicator(file.name)

      const response = await fetch(this.formTarget.action, {
        method: 'POST',
        headers: {
          'X-CSRF-Token': csrfToken,
          'Accept': 'application/json'
        },
        body: formData
      })

      if (response.ok) {
        const data = await response.json()
        this.addAttachmentToList(data)
        this.hideUploadingIndicator()
      } else {
        const errorData = await response.json()
        this.hideUploadingIndicator()
        alert(`Upload failed: ${errorData.errors?.join(', ') || 'Unknown error'}`)
      }
    } catch (error) {
      this.hideUploadingIndicator()
      console.error('Upload error:', error)
      alert('Upload failed. Please try again.')
    }
  }

  determineAttachmentType(file) {
    // Check if it's an image
    if (file.type.startsWith('image/')) {
      return 'before_photo' // Default to before_photo for images
    }
    // Check if it's a PDF or document
    if (file.type === 'application/pdf' || 
        file.type.includes('word') || 
        file.type.includes('document')) {
      return 'instruction'
    }
    return 'general'
  }

  showUploadingIndicator(fileName) {
    const indicator = document.createElement('div')
    indicator.id = 'upload-indicator'
    indicator.className = 'fixed bottom-4 right-4 bg-blue-600 text-white px-4 py-2 rounded-lg shadow-lg flex items-center space-x-2'
    indicator.innerHTML = `
      <svg class="animate-spin h-5 w-5 text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
        <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
        <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
      </svg>
      <span>Uploading ${fileName}...</span>
    `
    document.body.appendChild(indicator)
  }

  hideUploadingIndicator() {
    const indicator = document.getElementById('upload-indicator')
    if (indicator) {
      indicator.remove()
    }
  }

  addAttachmentToList(attachment) {
    // Reload the page to show the new attachment
    // In a more advanced implementation, we'd dynamically add the attachment to the DOM
    window.location.reload()
  }
}
