import { Controller } from "@hotwired/stimulus"
import Cropper from "cropperjs"

/**
 * Image Cropper Controller
 *
 * Provides user-controlled image cropping using Cropper.js
 * Supports various aspect ratios, zoom, rotation, and mobile touch gestures
 *
 * Usage:
 *   <div data-controller="image-cropper"
 *        data-image-cropper-aspect-ratio-value="1"
 *        data-image-cropper-lock-aspect-ratio-value="false"
 *        data-image-cropper-max-dimension-value="4096">
 *     ...
 *   </div>
 */
export default class extends Controller {
  static targets = [
    "fileInput",      // Original file input
    "preview",        // Image element for cropper
    "cropData",       // Hidden field storing JSON crop coordinates
    "modal",          // Cropper modal container
    "thumbnail",      // Preview thumbnail in form
    "thumbnailImage", // The img element inside thumbnail
    "aspectRatio",    // Aspect ratio selector buttons
    "zoomRange",      // Zoom slider
    "fileName"        // Display selected file name
  ]

  static values = {
    aspectRatio: { type: Number, default: 0 },      // 0 = free, 1 = 1:1, etc.
    lockAspectRatio: { type: Boolean, default: false },
    maxDimension: { type: Number, default: 4096 },
    minCropSize: { type: Number, default: 100 }
  }

  connect() {
    this.cropper = null
    this.currentFile = null
    this.scaledImageUrl = null
    this.originalImageDimensions = null
    console.log("Image cropper controller connected")
  }

  disconnect() {
    this.destroyCropper()
    if (this.scaledImageUrl) {
      URL.revokeObjectURL(this.scaledImageUrl)
    }
  }

  // Trigger file input click
  triggerFileSelect(event) {
    event.preventDefault()
    this.fileInputTarget.click()
  }

  // Handle file selection
  fileSelected(event) {
    const files = event.target.files
    if (files.length === 0) return

    const file = files[0]

    // Validate file type
    if (!file.type.startsWith('image/')) {
      alert('Please select an image file')
      return
    }

    this.currentFile = file
    this.loadImage(file)
  }

  // Load image and open cropper
  async loadImage(file) {
    try {
      // Create object URL for the file
      const imageUrl = URL.createObjectURL(file)

      // Load image to check dimensions
      const img = new Image()
      img.onload = () => {
        this.originalImageDimensions = {
          width: img.naturalWidth,
          height: img.naturalHeight
        }

        // Check if scaling is needed
        if (img.naturalWidth > this.maxDimensionValue || img.naturalHeight > this.maxDimensionValue) {
          this.scaleImageAndOpen(img, imageUrl)
        } else {
          this.openCropperWithImage(imageUrl)
        }
      }
      img.onerror = () => {
        URL.revokeObjectURL(imageUrl)
        alert('Failed to load image')
      }
      img.src = imageUrl
    } catch (error) {
      console.error('Error loading image:', error)
      alert('Failed to load image')
    }
  }

  // Scale image down if larger than max dimension
  scaleImageAndOpen(img, originalUrl) {
    const canvas = document.createElement('canvas')
    const ctx = canvas.getContext('2d')

    // Calculate new dimensions
    let { width, height } = img
    const maxDim = this.maxDimensionValue

    if (width > height) {
      if (width > maxDim) {
        height = Math.round((height * maxDim) / width)
        width = maxDim
      }
    } else {
      if (height > maxDim) {
        width = Math.round((width * maxDim) / height)
        height = maxDim
      }
    }

    canvas.width = width
    canvas.height = height
    ctx.drawImage(img, 0, 0, width, height)

    // Convert to blob and create URL
    canvas.toBlob((blob) => {
      URL.revokeObjectURL(originalUrl)
      this.scaledImageUrl = URL.createObjectURL(blob)
      this.openCropperWithImage(this.scaledImageUrl)
    }, 'image/jpeg', 0.92)
  }

  // Open cropper modal with image
  openCropperWithImage(imageUrl) {
    // Set image source
    this.previewTarget.src = imageUrl

    // Show modal
    this.modalTarget.classList.remove('hidden')
    document.body.classList.add('overflow-hidden')

    // Wait for image to load then initialize cropper
    this.previewTarget.onload = () => {
      this.initializeCropper()
    }
  }

  // Initialize Cropper.js
  initializeCropper() {
    this.destroyCropper()

    const aspectRatio = this.aspectRatioValue === 0 ? NaN : this.aspectRatioValue

    this.cropper = new Cropper(this.previewTarget, {
      aspectRatio: aspectRatio,
      viewMode: 1,
      dragMode: 'move',
      autoCropArea: 0.9,
      restore: false,
      guides: true,
      center: true,
      highlight: false,
      cropBoxMovable: true,
      cropBoxResizable: true,
      toggleDragModeOnDblclick: false,
      minCropBoxWidth: this.minCropSizeValue,
      minCropBoxHeight: this.minCropSizeValue,
      ready: () => {
        // Update zoom slider to match initial state
        if (this.hasZoomRangeTarget) {
          this.zoomRangeTarget.value = 1
        }
        this.updateAspectRatioButtons()
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
      scaleY: cropData.scaleY || 1
    }

    // Save to hidden field
    if (this.hasCropDataTarget) {
      this.cropDataTarget.value = JSON.stringify(cropCoordinates)
    }

    // Generate and show thumbnail preview
    this.generateThumbnail()

    // Update file name display
    if (this.hasFileNameTarget && this.currentFile) {
      this.fileNameTarget.textContent = this.currentFile.name
    }

    // Close modal
    this.closeModal()
  }

  // Cancel crop and close modal
  cancelCrop(event) {
    event.preventDefault()

    // Clear the file input
    this.fileInputTarget.value = ''
    this.currentFile = null

    // Clear crop data
    if (this.hasCropDataTarget) {
      this.cropDataTarget.value = ''
    }

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
    this.modalTarget.classList.add('hidden')
    document.body.classList.remove('overflow-hidden')
    this.destroyCropper()

    // Clean up scaled image URL
    if (this.scaledImageUrl) {
      URL.revokeObjectURL(this.scaledImageUrl)
      this.scaledImageUrl = null
    }
  }

  // Generate thumbnail preview
  generateThumbnail() {
    if (!this.cropper) return

    const canvas = this.cropper.getCroppedCanvas({
      width: 200,
      height: 200,
      imageSmoothingEnabled: true,
      imageSmoothingQuality: 'high'
    })

    if (canvas && this.hasThumbnailTarget) {
      const thumbnailUrl = canvas.toDataURL('image/jpeg', 0.8)

      if (this.hasThumbnailImageTarget) {
        this.thumbnailImageTarget.src = thumbnailUrl
      }

      this.thumbnailTarget.classList.remove('hidden')
    }
  }

  // Set aspect ratio
  setAspectRatio(event) {
    event.preventDefault()

    if (this.lockAspectRatioValue) return

    const ratio = parseFloat(event.currentTarget.dataset.ratio)
    this.aspectRatioValue = ratio

    if (this.cropper) {
      this.cropper.setAspectRatio(ratio === 0 ? NaN : ratio)
    }

    this.updateAspectRatioButtons()
  }

  // Update aspect ratio button states
  updateAspectRatioButtons() {
    if (!this.hasAspectRatioTarget) return

    this.aspectRatioTargets.forEach(button => {
      const buttonRatio = parseFloat(button.dataset.ratio)
      const isActive = buttonRatio === this.aspectRatioValue

      if (isActive) {
        button.setAttribute('data-active', 'true')
        button.classList.add('bg-primary', 'text-white')
        button.classList.remove('bg-white', 'text-gray-700')
      } else {
        button.removeAttribute('data-active')
        button.classList.remove('bg-primary', 'text-white')
        button.classList.add('bg-white', 'text-gray-700')
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
