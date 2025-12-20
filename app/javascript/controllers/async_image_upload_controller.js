import { Controller } from "@hotwired/stimulus"

/**
 * Async Image Upload Controller
 *
 * Provides immediate image upload functionality without form submission.
 * Works with services and products to upload images asynchronously.
 *
 * Usage:
 *   <div data-controller="async-image-upload"
 *        data-async-image-upload-upload-url-value="/manage/services/1/add_image"
 *        data-async-image-upload-remove-url-value="/manage/services/1/remove_image"
 *        data-async-image-upload-crop-url-value="/manage/services/1/crop_image">
 *     ...
 *   </div>
 */
export default class extends Controller {
  static targets = [
    "fileInput",       // Hidden file input
    "imageList",       // Container for uploaded images
    "uploadButton",    // Button that triggers file selection
    "uploadStatus",    // Status message display
    "template"         // Template for new image items
  ]

  static values = {
    uploadUrl: String,       // URL for uploading new images
    removeUrlPrefix: String, // URL prefix for removing images (append attachment_id)
    cropUrlPrefix: String,   // URL prefix for cropping images (append attachment_id)
    maxFileSize: { type: Number, default: 15728640 }, // 15MB
    maxFiles: { type: Number, default: 10 },
    allowedTypes: { type: String, default: "image/png,image/jpeg,image/gif,image/webp,image/heic,image/heif" },
    maxRetries: { type: Number, default: 3 },         // Number of retry attempts
    retryDelay: { type: Number, default: 1000 }       // Initial delay in ms (doubles each retry)
  }

  connect() {
    console.log("Async image upload controller connected")
    this.setupEventListeners()
  }

  disconnect() {
    // Clean up if needed
  }

  setupEventListeners() {
    // Handle file input change
    if (this.hasFileInputTarget) {
      this.fileInputTarget.addEventListener('change', this.handleFileSelect.bind(this))
    }

    // Handle upload button click
    if (this.hasUploadButtonTarget) {
      this.uploadButtonTarget.addEventListener('click', () => {
        this.fileInputTarget?.click()
      })
    }
  }

  // Handle file selection
  async handleFileSelect(event) {
    const files = event.target.files
    if (!files || files.length === 0) return

    // Validate files
    const validFiles = this.validateFiles(files)
    if (validFiles.length === 0) {
      event.target.value = '' // Reset input
      return
    }

    // Upload each file
    for (const file of validFiles) {
      await this.uploadFile(file)
    }

    // Reset file input
    event.target.value = ''
  }

  // Validate files before upload
  validateFiles(files) {
    const validFiles = []
    const allowedTypes = this.allowedTypesValue.split(',')

    for (let i = 0; i < files.length; i++) {
      const file = files[i]

      // Check file type
      if (!allowedTypes.includes(file.type)) {
        this.showStatus(`Invalid file type: ${file.name}. Allowed: PNG, JPEG, GIF, WebP, HEIC`, 'error')
        continue
      }

      // Check file size
      if (file.size > this.maxFileSizeValue) {
        this.showStatus(`File too large: ${file.name}. Maximum size is 15MB.`, 'error')
        continue
      }

      validFiles.push(file)
    }

    // Check max files
    if (validFiles.length > this.maxFilesValue) {
      this.showStatus(`Maximum ${this.maxFilesValue} files allowed`, 'error')
      return validFiles.slice(0, this.maxFilesValue)
    }

    return validFiles
  }

  // Upload a single file with retry logic
  async uploadFile(file, retryCount = 0) {
    if (!this.uploadUrlValue) {
      console.error("No upload URL configured")
      this.showStatus('Upload not configured. Please refresh and try again.', 'error')
      return
    }

    const isRetry = retryCount > 0
    const statusMessage = isRetry
      ? `Retrying upload of ${file.name} (attempt ${retryCount + 1}/${this.maxRetriesValue})...`
      : `Uploading ${file.name}...`

    this.showStatus(statusMessage, 'info')
    this.setButtonLoading(true)

    const formData = new FormData()
    formData.append('image', file)

    try {
      const response = await fetch(this.uploadUrlValue, {
        method: 'POST',
        headers: {
          'Accept': 'application/json',
          'X-CSRF-Token': this.getCSRFToken()
        },
        body: formData
      })

      if (response.ok) {
        const result = await response.json()
        this.addImageToList(result)
        this.showStatus(`${file.name} uploaded successfully`, 'success')
      } else {
        const errorData = await response.json().catch(() => ({}))
        const errorMessage = this.getReadableErrorMessage(response.status, errorData)
        throw new Error(errorMessage)
      }
    } catch (error) {
      console.error('Upload error:', error)

      // Check if we should retry (network errors or 5xx errors)
      if (this.shouldRetry(error, retryCount)) {
        const delay = this.retryDelayValue * Math.pow(2, retryCount) // Exponential backoff
        this.showStatus(`Upload failed. Retrying in ${delay / 1000}s...`, 'warning')

        await this.sleep(delay)
        return this.uploadFile(file, retryCount + 1)
      }

      this.showStatus(`Failed to upload ${file.name}: ${error.message}`, 'error')
    } finally {
      this.setButtonLoading(false)
    }
  }

  // Convert HTTP error codes to user-friendly messages
  getReadableErrorMessage(status, errorData) {
    if (errorData && errorData.error) {
      return errorData.error
    }

    switch (status) {
      case 400:
        return 'Invalid file. Please check the file and try again.'
      case 401:
        return 'Session expired. Please refresh the page and try again.'
      case 403:
        return 'Permission denied. You may not have access to upload files.'
      case 413:
        return 'File is too large. Maximum file size is 15MB.'
      case 422:
        return 'Invalid file type or corrupted file.'
      case 429:
        return 'Too many uploads. Please wait a moment and try again.'
      case 500:
      case 502:
      case 503:
      case 504:
        return 'Server temporarily unavailable. Please try again shortly.'
      default:
        return `Upload failed (error ${status}). Please try again.`
    }
  }

  // Determine if we should retry based on error type
  shouldRetry(error, retryCount) {
    if (retryCount >= this.maxRetriesValue) {
      return false
    }

    // Retry on network errors or timeout
    if (error.name === 'TypeError' || error.message.includes('network') || error.message.includes('fetch')) {
      return true
    }

    // Retry on server errors (5xx) - check for specific phrases
    const serverErrorPhrases = [
      'Server temporarily unavailable',
      'error 500',
      'error 502',
      'error 503',
      'error 504'
    ]
    if (serverErrorPhrases.some(phrase => error.message.includes(phrase))) {
      return true
    }

    // Don't retry on client errors (4xx) - these are permanent failures
    return false
  }

  // Sleep helper for retry delay
  sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms))
  }

  // Add uploaded image to the list
  addImageToList(imageData) {
    if (!this.hasImageListTarget) return

    const imageItem = this.createImageItem(imageData)
    this.imageListTarget.appendChild(imageItem)
  }

  // Create HTML for a new image item
  createImageItem(imageData) {
    const div = document.createElement('div')
    div.className = 'mb-4 border border-gray-200 rounded-lg image-management-item bg-white shadow-sm'
    div.dataset.imageId = imageData.attachment_id
    div.dataset.asyncImageUploadTarget = 'imageItem'

    const removeUrl = `${this.removeUrlPrefixValue}/${imageData.attachment_id}`
    const cropUrl = `${this.cropUrlPrefixValue}/${imageData.attachment_id}`
    // Escape filename to prevent XSS attacks
    const safeFilename = this.escapeHtml(imageData.filename)

    div.innerHTML = `
      <div class="flex flex-col sm:flex-row sm:items-center p-4 gap-4">
        <div class="flex-shrink-0 self-center sm:self-start relative">
          <img src="${imageData.thumbnail_url}"
               class="w-20 h-20 sm:w-24 sm:h-24 rounded-lg shadow-sm object-cover"
               id="thumbnail_${imageData.attachment_id}" />
        </div>
        <div class="flex-grow min-w-0">
          <p class="text-sm font-medium text-gray-700 mb-3 truncate" title="${safeFilename}">
            ${safeFilename}
          </p>
          <div class="space-y-3 sm:space-y-2">
            <div class="flex flex-wrap gap-2">
              <button type="button"
                      class="inline-flex items-center px-3 py-2 text-sm font-medium text-primary hover:text-primary/80 hover:bg-light rounded-md transition-colors cursor-pointer"
                      data-action="click->simple-image-cropper#openCropper"
                      data-image-url="${imageData.full_url}"
                      data-crop-url="${cropUrl}">
                <svg class="w-4 h-4 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"></path>
                </svg>
                Crop
              </button>
              <button type="button"
                      class="inline-flex items-center px-3 py-2 text-sm font-medium text-red-600 hover:text-red-700 hover:bg-red-50 rounded-md transition-colors cursor-pointer"
                      data-action="click->async-image-upload#removeImage"
                      data-remove-url="${removeUrl}">
                <svg class="w-4 h-4 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"></path>
                </svg>
                Remove
              </button>
            </div>
          </div>
        </div>
      </div>
    `

    return div
  }

  // Remove an image
  async removeImage(event) {
    event.preventDefault()

    const button = event.currentTarget
    const removeUrl = button.dataset.removeUrl
    const imageItem = button.closest('.image-management-item')

    if (!removeUrl || !imageItem) {
      console.error("Missing remove URL or image item")
      return
    }

    if (!confirm('Are you sure you want to remove this image?')) {
      return
    }

    button.disabled = true
    button.textContent = 'Removing...'

    try {
      const response = await fetch(removeUrl, {
        method: 'DELETE',
        headers: {
          'Accept': 'application/json',
          'X-CSRF-Token': this.getCSRFToken()
        }
      })

      if (response.ok) {
        imageItem.remove()
        this.showStatus('Image removed successfully', 'success')
      } else {
        const error = await response.json()
        throw new Error(error.error || 'Failed to remove image')
      }
    } catch (error) {
      console.error('Remove error:', error)
      this.showStatus(`Failed to remove image: ${error.message}`, 'error')
      button.disabled = false
      button.innerHTML = `
        <svg class="w-4 h-4 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"></path>
        </svg>
        Remove
      `
    }
  }

  // Show status message
  showStatus(message, type = 'info') {
    if (!this.hasUploadStatusTarget) {
      console.log(`[${type}] ${message}`)
      return
    }

    const statusClasses = {
      info: 'text-blue-600 bg-blue-50 border-blue-200',
      success: 'text-green-600 bg-green-50 border-green-200',
      warning: 'text-yellow-600 bg-yellow-50 border-yellow-200',
      error: 'text-red-600 bg-red-50 border-red-200'
    }

    this.uploadStatusTarget.className = `mt-3 p-3 rounded-lg border text-sm font-medium ${statusClasses[type] || statusClasses.info}`
    this.uploadStatusTarget.textContent = message
    this.uploadStatusTarget.classList.remove('hidden')

    // Auto-hide success messages after 3 seconds
    if (type === 'success') {
      setTimeout(() => {
        this.uploadStatusTarget.classList.add('hidden')
      }, 3000)
    }

    // Auto-hide warning messages after 5 seconds
    if (type === 'warning') {
      setTimeout(() => {
        this.uploadStatusTarget.classList.add('hidden')
      }, 5000)
    }
  }

  // Set button loading state
  setButtonLoading(loading) {
    if (!this.hasUploadButtonTarget) return

    if (loading) {
      this.uploadButtonTarget.disabled = true
      this.uploadButtonTarget.innerHTML = `
        <svg class="animate-spin w-5 h-5 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
          <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
        </svg>
        Uploading...
      `
    } else {
      this.uploadButtonTarget.disabled = false
      this.uploadButtonTarget.innerHTML = `
        <svg class="w-5 h-5 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M15 13l-3-3m0 0l-3 3m3-3v12"></path>
        </svg>
        Choose Files
      `
    }
  }

  // Get CSRF token from meta tag
  getCSRFToken() {
    const metaTag = document.querySelector('meta[name="csrf-token"]')
    return metaTag ? metaTag.content : ''
  }

  // Escape HTML to prevent XSS attacks
  escapeHtml(text) {
    if (!text) return ''
    const div = document.createElement('div')
    div.textContent = text
    return div.innerHTML
  }
}
