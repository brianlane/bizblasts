import { Controller } from "@hotwired/stimulus"
import Cropper from "cropperjs"

/**
 * Gallery Image Cropper Controller
 *
 * Provides cropping functionality for existing images in a gallery.
 * Unlike the standard image-cropper, this works with already-uploaded images
 * loaded from URLs rather than file inputs.
 *
 * Usage:
 *   <div data-controller="gallery-image-cropper"
 *        data-gallery-image-cropper-aspect-ratio-value="1"
 *        data-gallery-image-cropper-lock-aspect-ratio-value="false">
 *     ...
 *   </div>
 */
export default class extends Controller {
  static targets = [
    "modal",          // Cropper modal container
    "preview",        // Image element for cropper
    "zoomRange",      // Zoom slider
    "aspectRatio"     // Aspect ratio selector buttons
  ]

  static values = {
    aspectRatio: { type: Number, default: 1 },
    lockAspectRatio: { type: Boolean, default: false },
    maxDimension: { type: Number, default: 4096 },
    minCropSize: { type: Number, default: 100 }
  }

  connect() {
    this.cropper = null
    this.currentAttachmentId = null
    this.currentCropDataField = null
    this.currentThumbnail = null
    this.currentCropUrl = null
    this._fallbackModal = null
    
    // Bind Turbo event handler
    this.handleTurboBeforeCache = this.handleTurboBeforeCache.bind(this)
    document.addEventListener('turbo:before-cache', this.handleTurboBeforeCache)
    
    if (this.isDevEnvironment()) {
      console.log("Gallery image cropper controller connected", {
        hasModal: this.hasModalTarget,
        hasPreview: this.hasPreviewTarget
      })
    }
  }
  
  // Check if we're in development environment
  isDevEnvironment() {
    return window.location.hostname.includes('lvh.me') || 
           window.location.hostname === 'localhost' ||
           window.location.hostname === '127.0.0.1'
  }
  
  // Handle Turbo cache events
  handleTurboBeforeCache() {
    this.destroyCropper()
    const modal = this.getModal()
    if (modal && !modal.classList.contains('hidden')) {
      modal.classList.add('hidden')
      document.body.classList.remove('overflow-hidden')
    }
  }
  
  // Get modal with fallback
  getModal() {
    if (this.hasModalTarget) {
      return this.modalTarget
    }
    // Fallback search
    let modal = this.element.querySelector('[data-gallery-image-cropper-target="modal"]')
    if (modal) {
      this._fallbackModal = modal
      return modal
    }
    // Check cached
    if (this._fallbackModal && document.contains(this._fallbackModal)) {
      return this._fallbackModal
    }
    // Search by ID
    const possibleIds = ['gallery_photo_cropper', 'gallery_image_cropper_modal']
    for (const id of possibleIds) {
      modal = document.getElementById(id)
      if (modal && this.element.contains(modal)) {
        this._fallbackModal = modal
        return modal
      }
    }
    return null
  }
  
  // Get preview element with fallback
  getPreview() {
    if (this.hasPreviewTarget) {
      return this.previewTarget
    }
    const modal = this.getModal()
    return modal?.querySelector('[data-gallery-image-cropper-target="preview"]')
  }

  disconnect() {
    this.destroyCropper()
    this._fallbackModal = null
    document.removeEventListener('turbo:before-cache', this.handleTurboBeforeCache)
    
    // Ensure modal is closed
    const modal = this.getModal()
    if (modal && !modal.classList.contains('hidden')) {
      modal.classList.add('hidden')
      document.body.classList.remove('overflow-hidden')
    }
  }

  // Open cropper for a specific image (for form-based cropping)
  openCropper(event) {
    event.preventDefault()

    const button = event.currentTarget
    const imageUrl = button.dataset.imageUrl
    const attachmentId = button.dataset.attachmentId
    const cropDataFieldId = button.dataset.cropDataField
    const thumbnailSelector = button.dataset.thumbnailSelector

    if (this.isDevEnvironment()) {
      console.log('Opening cropper for form-based image:', { imageUrl, attachmentId })
    }

    if (!imageUrl || !attachmentId) {
      console.error("Missing image URL or attachment ID")
      return
    }

    const modal = this.getModal()
    const preview = this.getPreview()
    
    if (!modal) {
      console.error("Modal not found for gallery image cropper")
      alert("Cropper modal not found. Please refresh the page and try again.")
      return
    }
    
    if (!preview) {
      console.error("Preview element not found in modal")
      alert("Cropper preview element not found. Please refresh the page and try again.")
      return
    }

    this.currentAttachmentId = attachmentId
    this.currentCropDataField = document.getElementById(cropDataFieldId)
    this.currentThumbnail = thumbnailSelector ? document.querySelector(thumbnailSelector) : null
    this.currentCropUrl = null  // Form-based cropping doesn't use a crop URL

    // Open modal first so container dimensions are available
    modal.classList.remove('hidden')
    document.body.classList.add('overflow-hidden')

    // Set up event handlers
    const loadHandler = () => {
      if (this.isDevEnvironment()) {
        console.log('Image loaded successfully')
      }
      preview.removeEventListener('load', loadHandler)
      preview.removeEventListener('error', errorHandler)
      // Small delay to ensure modal is fully rendered
      requestAnimationFrame(() => {
        this.initializeCropper()
      })
    }

    const errorHandler = (e) => {
      console.error("Image load error:", e)
      preview.removeEventListener('load', loadHandler)
      preview.removeEventListener('error', errorHandler)
      this.closeModal()
      alert("Failed to load image for cropping")
    }

    // Check if image is already loaded (cached) with the same URL
    if (preview.src === imageUrl && preview.complete && preview.naturalWidth > 0) {
      if (this.isDevEnvironment()) {
        console.log('Image already loaded from cache')
      }
      requestAnimationFrame(() => {
        this.initializeCropper()
      })
      return
    }

    // Add event listeners before changing src
    preview.addEventListener('load', loadHandler)
    preview.addEventListener('error', errorHandler)

    // Set the image source (triggers load or error)
    preview.src = imageUrl
  }

  // Open cropper for an existing image with server-side crop endpoint
  openCropperForExisting(event) {
    event.preventDefault()
    event.stopPropagation()

    const button = event.currentTarget
    const imageUrl = button.dataset.imageUrl
    const cropUrl = button.dataset.cropUrl

    if (this.isDevEnvironment()) {
      console.log('Opening cropper for existing image:', { imageUrl, cropUrl })
    }

    if (!imageUrl || !cropUrl) {
      console.error("Missing image URL or crop URL")
      return
    }

    const modal = this.getModal()
    const preview = this.getPreview()
    
    if (!modal) {
      console.error("Modal not found for gallery image cropper")
      alert("Cropper modal not found. Please refresh the page and try again.")
      return
    }
    
    if (!preview) {
      console.error("Preview element not found in modal")
      alert("Cropper preview element not found. Please refresh the page and try again.")
      return
    }

    this.currentAttachmentId = null
    this.currentCropDataField = null
    this.currentThumbnail = null
    this.currentCropUrl = cropUrl

    // Open modal first so container dimensions are available
    modal.classList.remove('hidden')
    document.body.classList.add('overflow-hidden')

    // Set up event handlers
    const loadHandler = () => {
      if (this.isDevEnvironment()) {
        console.log('Image loaded successfully')
      }
      preview.removeEventListener('load', loadHandler)
      preview.removeEventListener('error', errorHandler)
      // Small delay to ensure modal is fully rendered
      requestAnimationFrame(() => {
        this.initializeCropper()
      })
    }

    const errorHandler = (e) => {
      console.error("Image load error:", e)
      preview.removeEventListener('load', loadHandler)
      preview.removeEventListener('error', errorHandler)
      this.closeModal()
      alert("Failed to load image for cropping")
    }

    // Check if image is already loaded (cached) with the same URL
    if (preview.src === imageUrl && preview.complete && preview.naturalWidth > 0) {
      if (this.isDevEnvironment()) {
        console.log('Image already loaded from cache')
      }
      requestAnimationFrame(() => {
        this.initializeCropper()
      })
      return
    }

    // Add event listeners before changing src
    preview.addEventListener('load', loadHandler)
    preview.addEventListener('error', errorHandler)

    // Set the image source (triggers load or error)
    preview.src = imageUrl
  }

  // Initialize Cropper.js with touch support
  initializeCropper() {
    this.destroyCropper()
    
    const preview = this.getPreview()
    if (!preview) {
      console.error("Preview element not found for cropper initialization")
      return
    }

    const aspectRatio = this.aspectRatioValue === 0 ? NaN : this.aspectRatioValue
    const isTouchDevice = 'ontouchstart' in window || navigator.maxTouchPoints > 0

    // Get the container dimensions for proper sizing
    // The wrapper is the parent of the preview image
    const wrapper = preview.parentElement
    const containerWidth = wrapper.clientWidth
    const containerHeight = wrapper.clientHeight

    if (this.isDevEnvironment()) {
      console.log(`Initializing cropper with container size: ${containerWidth}x${containerHeight}`)
    }

    this.cropper = new Cropper(preview, {
      aspectRatio: aspectRatio,
      viewMode: 2,  // Restrict the crop box and canvas to not exceed the container
      dragMode: 'move',
      autoCropArea: 0.8,
      restore: false,
      guides: true,
      center: true,
      highlight: false,
      cropBoxMovable: true,
      cropBoxResizable: true,
      toggleDragModeOnDblclick: false,
      minCropBoxWidth: this.minCropSizeValue,
      minCropBoxHeight: this.minCropSizeValue,
      background: true,
      modal: true,
      // Touch-specific settings
      responsive: true,
      checkCrossOrigin: false,  // Disable cross-origin check since we're using proxy URLs
      checkOrientation: true,
      // Smooth touch handling
      wheelZoomRatio: isTouchDevice ? 0.05 : 0.1,
      ready: () => {
        if (this.hasZoomRangeTarget) {
          this.zoomRangeTarget.value = 1
        }
        this.updateAspectRatioButtons()

        // Ensure cropper container fits properly
        // Search from the wrapper element, not from this.element
        const cropperContainer = wrapper.querySelector('.cropper-container')
        if (cropperContainer) {
          cropperContainer.style.maxWidth = '100%'
          cropperContainer.style.maxHeight = containerHeight + 'px'
          cropperContainer.style.overflow = 'hidden'
        }

        // Add touch-friendly class to crop box on touch devices
        if (isTouchDevice) {
          const cropBox = wrapper.querySelector('.cropper-crop-box')
          if (cropBox) {
            cropBox.style.touchAction = 'none'
          }
        }

        console.log('Cropper initialized successfully')
      }
    })
  }

  // Destroy cropper instance
  destroyCropper() {
    if (this.cropper) {
      this.cropper.destroy()
      this.cropper = null
    }
  }

  // Apply crop and close modal
  applyCrop(event) {
    event.preventDefault()

    if (!this.cropper) return

    const cropData = this.cropper.getData(true)

    // Store crop coordinates
    const cropCoordinates = {
      x: Math.round(cropData.x),
      y: Math.round(cropData.y),
      width: Math.round(cropData.width),
      height: Math.round(cropData.height),
      rotate: Math.round(cropData.rotate || 0),
      scaleX: cropData.scaleX || 1,
      scaleY: cropData.scaleY || 1,
      attachment_id: this.currentAttachmentId
    }

    // If we have a server crop URL, send the crop data directly to the server
    if (this.currentCropUrl) {
      this.submitCropToServer(cropCoordinates)
      return
    }

    // Otherwise, save to hidden field for form submission
    if (this.currentCropDataField) {
      this.currentCropDataField.value = JSON.stringify(cropCoordinates)
    }

    // Update thumbnail preview with cropped version
    this.updateThumbnail()

    // Mark the image item as having pending crop
    this.markImageAsCropped()

    // Close modal
    this.closeModal()
  }

  // Submit crop data to server for immediate processing
  async submitCropToServer(cropCoordinates) {
    const button = this.element.querySelector('[data-action*="applyCrop"]')
    const originalText = button?.textContent

    try {
      // Show loading state
      if (button) {
        button.disabled = true
        button.textContent = 'Applying...'
      }

      const response = await fetch(this.currentCropUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'X-CSRF-Token': this.getCSRFToken()
        },
        body: JSON.stringify({ crop_data: cropCoordinates })
      })

      if (response.ok) {
        const result = await response.json()
        // Close modal and reload the page to show updated image
        this.closeModal()
        // Reload the page to reflect the changes
        window.location.reload()
      } else {
        const error = await response.json()
        throw new Error(error.error || 'Failed to crop image')
      }
    } catch (error) {
      console.error('Failed to apply crop:', error)
      alert(error.message || 'Failed to apply crop. Please try again.')
    } finally {
      // Restore button state
      if (button) {
        button.disabled = false
        button.textContent = originalText
      }
    }
  }

  // Get CSRF token from meta tag
  getCSRFToken() {
    const metaTag = document.querySelector('meta[name="csrf-token"]')
    return metaTag ? metaTag.content : ''
  }

  // Update thumbnail with cropped preview
  updateThumbnail() {
    if (!this.cropper || !this.currentThumbnail) return

    const canvas = this.cropper.getCroppedCanvas({
      width: 200,
      height: 200,
      imageSmoothingEnabled: true,
      imageSmoothingQuality: 'high'
    })

    if (canvas) {
      const thumbnailUrl = canvas.toDataURL('image/jpeg', 0.8)
      this.currentThumbnail.src = thumbnailUrl
    }
  }

  // Mark the image item visually as having a pending crop
  markImageAsCropped() {
    if (!this.currentAttachmentId) return

    const imageItem = this.element.querySelector(`[data-image-id="${this.currentAttachmentId}"]`)
    if (imageItem) {
      // Add visual indicator
      imageItem.classList.add('ring-2', 'ring-primary', 'ring-offset-2')

      // Add/update badge
      let badge = imageItem.querySelector('.crop-pending-badge')
      if (!badge) {
        badge = document.createElement('span')
        badge.className = 'crop-pending-badge absolute top-2 right-2 bg-primary text-white text-xs px-2 py-1 rounded-full'
        badge.textContent = 'Crop pending'
        const imageContainer = imageItem.querySelector('.relative') || imageItem
        imageContainer.classList.add('relative')
        imageContainer.appendChild(badge)
      }
    }
  }

  // Cancel crop and close modal
  cancelCrop(event) {
    event.preventDefault()
    this.closeModal()
  }

  // Reset crop to default
  resetCrop(event) {
    event.preventDefault()
    if (this.cropper) {
      this.cropper.reset()
    }
  }

  // Close modal
  closeModal() {
    const modal = this.getModal()
    if (modal) {
      modal.classList.add('hidden')
    }
    document.body.classList.remove('overflow-hidden')
    this.destroyCropper()
    this.currentAttachmentId = null
    this.currentCropDataField = null
    this.currentThumbnail = null
    this.currentCropUrl = null
  }

  // Set aspect ratio
  setAspectRatio(event) {
    event.preventDefault()

    console.log('setAspectRatio called')

    if (this.lockAspectRatioValue) {
      console.log('Aspect ratio is locked, ignoring')
      return
    }

    const ratio = parseFloat(event.currentTarget.dataset.ratio)
    console.log(`Setting aspect ratio to: ${ratio}`)
    this.aspectRatioValue = ratio

    if (this.cropper) {
      this.cropper.setAspectRatio(ratio === 0 ? NaN : ratio)
      console.log('Cropper aspect ratio updated')
    } else {
      console.warn('Cropper not initialized')
    }

    this.updateAspectRatioButtons()
  }

  // Update aspect ratio button states
  updateAspectRatioButtons() {
    if (!this.hasAspectRatioTarget) {
      console.log('No aspect ratio targets found')
      return
    }

    console.log(`Updating ${this.aspectRatioTargets.length} aspect ratio buttons, current value: ${this.aspectRatioValue}`)

    this.aspectRatioTargets.forEach(button => {
      const buttonRatio = parseFloat(button.dataset.ratio)
      const isActive = buttonRatio === this.aspectRatioValue

      if (isActive) {
        button.setAttribute('data-active', 'true')
        button.classList.add('bg-primary', 'text-white', 'border-primary')
        button.classList.remove('bg-white', 'text-gray-700', 'border-gray-300')
      } else {
        button.removeAttribute('data-active')
        button.classList.remove('bg-primary', 'text-white', 'border-primary')
        button.classList.add('bg-white', 'text-gray-700', 'border-gray-300')
      }
    })
  }

  // Zoom controls
  zoomIn(event) {
    event.preventDefault()
    if (this.cropper) {
      this.cropper.zoom(0.1)
      this.updateZoomSlider()
    }
  }

  zoomOut(event) {
    event.preventDefault()
    if (this.cropper) {
      this.cropper.zoom(-0.1)
      this.updateZoomSlider()
    }
  }

  zoomTo(event) {
    if (this.cropper) {
      const zoomLevel = parseFloat(event.target.value)
      const imageData = this.cropper.getImageData()
      const currentZoom = imageData.width / imageData.naturalWidth
      const zoomDelta = zoomLevel - currentZoom
      this.cropper.zoom(zoomDelta)
    }
  }

  updateZoomSlider() {
    if (this.hasZoomRangeTarget && this.cropper) {
      const imageData = this.cropper.getImageData()
      const currentZoom = imageData.width / imageData.naturalWidth
      this.zoomRangeTarget.value = Math.min(Math.max(currentZoom, 0.1), 3)
    }
  }

  // Rotation controls
  rotateLeft(event) {
    event.preventDefault()
    if (this.cropper) {
      this.cropper.rotate(-90)
    }
  }

  rotateRight(event) {
    event.preventDefault()
    if (this.cropper) {
      this.cropper.rotate(90)
    }
  }

  // Prevent event propagation (for modal click handling)
  stopPropagation(event) {
    event.stopPropagation()
  }
}
