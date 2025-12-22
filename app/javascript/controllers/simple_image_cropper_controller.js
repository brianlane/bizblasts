import { Controller } from "@hotwired/stimulus"

/**
 * Simple Image Cropper Controller
 *
 * A drag-to-reposition style cropper that's simpler and more mobile-friendly
 * than traditional crop box interfaces.
 *
 * Supports two modes:
 * 1. Existing images: Load from URL, crop, send to server endpoint
 * 2. File uploads: Select file, crop, store data in hidden field for form submission
 *
 * Usage for existing images:
 *   <div data-controller="simple-image-cropper">
 *     <button data-action="click->simple-image-cropper#openCropper"
 *             data-image-url="..." data-crop-url="...">Crop</button>
 *   </div>
 *
 * Usage for file uploads:
 *   <div data-controller="simple-image-cropper">
 *     <input type="file" data-simple-image-cropper-target="fileInput"
 *            data-action="change->simple-image-cropper#fileSelected">
 *     <input type="hidden" data-simple-image-cropper-target="cropData">
 *   </div>
 */
export default class extends Controller {
  static targets = [
    "modal",
    "viewport",
    "image",
    "zoomSlider",
    "fileInput",      // For file upload mode
    "cropData",       // Hidden field for storing crop JSON
    "thumbnail",      // Preview thumbnail container
    "thumbnailImage", // The img element inside thumbnail
    "fileName"        // Display selected file name
  ]

  static values = {
    aspectRatio: { type: Number, default: 1 },  // 1 = square, 0 = free
    viewportSize: { type: Number, default: 300 },
    minZoom: { type: Number, default: 1 },
    maxZoom: { type: Number, default: 3 }
  }

  connect() {
    this.currentCropUrl = null
    this.imageLoaded = false
    this.zoom = 1
    this.minZoom = 1
    this.maxZoom = 3
    // Center of the viewport in *image pixel* coordinates (stable math).
    this.center = { x: 0, y: 0 }
    // Computed translation in viewport pixels (derived from center+zoom).
    this.position = { x: 0, y: 0 }
    this.isDragging = false
    this.dragStart = { x: 0, y: 0 }
    this.imageNaturalSize = { width: 0, height: 0 }
    
    // File upload mode state
    this.currentFile = null
    this.currentImageUrl = null  // Object URL for file preview
    this.isFileUploadMode = false
    
    // Cache for fallback modal reference
    this._fallbackModal = null

    // Bind methods for event listeners
    this.handleMouseMove = this.handleMouseMove.bind(this)
    this.handleMouseUp = this.handleMouseUp.bind(this)
    this.handleTouchMove = this.handleTouchMove.bind(this)
    this.handleTouchEnd = this.handleTouchEnd.bind(this)
    
    // Bind Turbo event handler
    this.handleTurboBeforeCache = this.handleTurboBeforeCache.bind(this)
    document.addEventListener('turbo:before-cache', this.handleTurboBeforeCache)

    // Debug logging only in development
    if (this.isDevEnvironment()) {
      console.log("🖼️ Simple image cropper connected", {
        hasModal: this.hasModalTarget,
        hasViewport: this.hasViewportTarget,
        hasImage: this.hasImageTarget,
        hasZoomSlider: this.hasZoomSliderTarget,
        hasFileInput: this.hasFileInputTarget,
        hasCropData: this.hasCropDataTarget,
        element: this.element
      })
    }
  }
  
  // Handle Turbo cache events - ensure modal is hidden before caching
  handleTurboBeforeCache() {
    // Close modal before Turbo caches the page to avoid stale state
    const modal = this.getModal()
    if (modal && !modal.classList.contains('hidden')) {
      modal.classList.add('hidden')
      document.body.classList.remove('overflow-hidden')
    }
    this.resetState()
  }
  
  // Check if we're in development environment
  isDevEnvironment() {
    return window.location.hostname.includes('lvh.me') || 
           window.location.hostname === 'localhost' ||
           window.location.hostname === '127.0.0.1'
  }
  
  // Get modal element with fallback for Turbo caching issues
  getModal() {
    // First try Stimulus target
    if (this.hasModalTarget) {
      return this.modalTarget
    }
    
    // Fallback: search within controller scope
    let modal = this.element.querySelector('[data-simple-image-cropper-target="modal"]')
    if (modal) {
      this._fallbackModal = modal
      return modal
    }
    
    // Last resort: check cached fallback
    if (this._fallbackModal && document.contains(this._fallbackModal)) {
      return this._fallbackModal
    }
    
    // Search for modal by common ID patterns (for Turbo reconnection issues)
    const possibleIds = [
      'service_image_cropper', 
      'product_image_cropper', 
      'gallery_photo_cropper',
      'photo_simple_cropper_modal',
      'logo_simple_cropper_modal',
      'simple_image_cropper_modal'
    ]
    for (const id of possibleIds) {
      modal = document.getElementById(id)
      if (modal && this.element.contains(modal)) {
        this._fallbackModal = modal
        return modal
      }
    }
    
    return null
  }
  
  // Get viewport element with fallback
  getViewport() {
    if (this.hasViewportTarget) {
      return this.viewportTarget
    }
    const modal = this.getModal()
    return modal?.querySelector('[data-simple-image-cropper-target="viewport"]')
  }
  
  // Get image element with fallback
  getImage() {
    if (this.hasImageTarget) {
      return this.imageTarget
    }
    const modal = this.getModal()
    return modal?.querySelector('[data-simple-image-cropper-target="image"]')
  }
  
  // Get zoom slider with fallback
  getZoomSlider() {
    if (this.hasZoomSliderTarget) {
      return this.zoomSliderTarget
    }
    const modal = this.getModal()
    return modal?.querySelector('[data-simple-image-cropper-target="zoomSlider"]')
  }

  viewportSize() {
    // Use the *actual rendered* viewport size to prevent drift into black space
    // when CSS/layout makes the element size differ from the configured value.
    const viewport = this.getViewport()
    if (viewport) {
      const rect = viewport.getBoundingClientRect()
      
      if (this.isDevEnvironment()) {
        console.log('[Cropper] Viewport rect:', { 
          width: rect.width, 
          height: rect.height,
          configuredSize: this.viewportSizeValue
        })
      }
      
      // Use the LARGER dimension to ensure image covers the entire viewport
      // even if it's not perfectly square
      const size = Math.max(rect.width, rect.height)
      
      // Ensure we have a valid size (not 0 when modal is hidden)
      if (size > 0) {
        return size
      }
      
      // Fallback: try to get size from style attribute
      const styleWidth = parseInt(viewport.style.width, 10)
      const styleHeight = parseInt(viewport.style.height, 10)
      if (styleWidth > 0 && styleHeight > 0) {
        return Math.max(styleWidth, styleHeight)
      }
    }
    
    // Final fallback to configured value
    return this.viewportSizeValue
  }

  disconnect() {
    this.removeGlobalListeners()
    this._fallbackModal = null
    
    // Remove Turbo event listener
    document.removeEventListener('turbo:before-cache', this.handleTurboBeforeCache)
    
    // Clean up object URL
    if (this.currentImageUrl) {
      URL.revokeObjectURL(this.currentImageUrl)
      this.currentImageUrl = null
    }
    
    // Ensure modal is closed
    const modal = this.getModal()
    if (modal && !modal.classList.contains('hidden')) {
      modal.classList.add('hidden')
      document.body.classList.remove('overflow-hidden')
    }
  }

  // Open cropper modal for an existing image
  openCropper(event) {
    event.preventDefault()
    event.stopPropagation()

    if (this.isDevEnvironment()) {
      console.log('🖼️ openCropper called')
    }

    const button = event.currentTarget
    const imageUrl = button.dataset.imageUrl
    const cropUrl = button.dataset.cropUrl

    if (this.isDevEnvironment()) {
      console.log('Opening simple cropper:', { imageUrl, cropUrl })
    }

    if (!imageUrl || !cropUrl) {
      if (this.isDevEnvironment()) {
        console.error("Missing image URL or crop URL")
        console.error("Button dataset:", button.dataset)
      }
      alert("Missing image URL or crop URL - check data attributes on button")
      return
    }

    // Get modal with fallback methods
    const modal = this.getModal()
    if (!modal) {
      if (this.isDevEnvironment()) {
        console.error("Modal not found! Attempted fallback search also failed.")
        console.error("Controller element:", this.element)
        console.error("hasModalTarget:", this.hasModalTarget)
      }
      
      // Try one more time after a brief delay (for Turbo timing issues)
      setTimeout(() => {
        const delayedModal = this.getModal()
        if (delayedModal) {
          if (this.isDevEnvironment()) {
            console.log("Modal found after delay, retrying...")
          }
          this.currentCropUrl = cropUrl
          this.resetState()
          this.showModal(delayedModal)
          this.loadImage(imageUrl)
        } else {
          alert("Cropper modal not found. Please refresh the page and try again.")
        }
      }, 100)
      return
    }

    this.currentCropUrl = cropUrl
    this.resetState()

    // Show modal
    if (this.isDevEnvironment()) {
      console.log('Showing modal...')
    }
    this.showModal(modal)

    // Load image
    this.loadImage(imageUrl)
  }

  // ==========================================
  // FILE UPLOAD MODE - For new file uploads
  // ==========================================

  // Trigger file input click (for custom upload buttons)
  triggerFileSelect(event) {
    event.preventDefault()
    if (this.hasFileInputTarget) {
      this.fileInputTarget.click()
    }
  }

  // Handle file selection from input
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
    this.isFileUploadMode = true
    this.currentCropUrl = null  // No server endpoint in file upload mode

    // Clean up previous object URL
    if (this.currentImageUrl) {
      URL.revokeObjectURL(this.currentImageUrl)
    }

    // Create object URL for the file
    this.currentImageUrl = URL.createObjectURL(file)

    // Get modal and open it
    const modal = this.getModal()
    if (!modal) {
      if (this.isDevEnvironment()) {
        console.error("Modal not found for file upload cropping")
      }
      alert("Cropper modal not found. Please refresh the page.")
      return
    }

    this.resetState()
    this.showModal(modal)
    this.loadImage(this.currentImageUrl)

    // Update file name display if available
    if (this.hasFileNameTarget) {
      this.fileNameTarget.textContent = file.name
    }
  }

  // ==========================================
  // SHARED METHODS
  // ==========================================
  
  // Show the modal with proper setup
  showModal(modal) {
    modal.classList.remove('hidden')
    document.body.classList.add('overflow-hidden')
    
    // Ensure modal is visible before we try to get dimensions
    requestAnimationFrame(() => {
      // Force a reflow to ensure the modal is rendered
      modal.offsetHeight
    })
  }

  loadImage(imageUrl) {
    if (this.isDevEnvironment()) {
      console.log('[Cropper] Loading image:', imageUrl)
    }

    // For S3/CloudFront URLs, we need to try loading without CORS first
    // because S3 may not have CORS headers configured
    const img = new Image()

    // Store the URL for later use
    this._currentLoadingUrl = imageUrl

    const handleSuccess = () => {
      if (this.isDevEnvironment()) {
        console.log('[Cropper] Image loaded successfully:', img.naturalWidth, 'x', img.naturalHeight)
      }
      
      this.imageNaturalSize = { width: img.naturalWidth, height: img.naturalHeight }
      
      const imageEl = this.getImage()
      if (imageEl) {
        // For the display image, we don't need CORS - just show it
        imageEl.crossOrigin = null
        imageEl.src = imageUrl
        this.imageLoaded = true
        
        // Wait for the image element to load
        imageEl.onload = () => {
          this.waitForModalRender(() => {
            this.calculateInitialZoom()
            this.centerImage()
            this.updateImageTransform()
            
            setTimeout(() => {
              this.syncZoomSlider()
            }, 100)

            if (this.isDevEnvironment()) {
              console.log('[Cropper] Cropper initialized:', {
                viewportSize: this.viewportSize(),
                imageSize: this.imageNaturalSize,
                zoom: this.zoom
              })
            }
          })
        }
        
        let cacheBustAttempted = false
        imageEl.onerror = () => {
          if (this.isDevEnvironment()) {
            console.error('[Cropper] Display image failed to load')
          }
          // Try one more time with a cache-busting parameter (limit to one retry)
          if (!cacheBustAttempted) {
            cacheBustAttempted = true
            const bustUrl = imageUrl + (imageUrl.includes('?') ? '&' : '?') + '_t=' + Date.now()
            imageEl.src = bustUrl
          } else {
            if (this.isDevEnvironment()) {
              console.error('[Cropper] Cache-bust retry also failed')
            }
            this.closeModal()
            alert('Failed to load image for cropping. The image may be inaccessible.')
          }
        }
      } else {
        if (this.isDevEnvironment()) {
          console.error('[Cropper] Image element not found in modal')
        }
        this.closeModal()
        alert('Failed to initialize cropper. Please try again.')
      }
    }

    const handleError = (e) => {
      if (this.isDevEnvironment()) {
        console.error('[Cropper] Pre-load failed:', e?.type || e, 'URL:', imageUrl)
      }

      // Try without crossOrigin
      if (img.crossOrigin) {
        if (this.isDevEnvironment()) {
          console.log('[Cropper] Retrying without CORS...')
        }
        const retryImg = new Image()
        retryImg.onload = handleSuccess
        retryImg.onerror = (retryError) => {
          if (this.isDevEnvironment()) {
            console.error('[Cropper] Retry without CORS also failed:', retryError?.type || retryError)
          }

          // Last resort: try to load directly in the image element
          if (this.isDevEnvironment()) {
            console.log('[Cropper] Attempting direct load in display element...')
          }
          const imageEl = this.getImage()
          if (imageEl) {
            imageEl.onload = () => {
              if (this.isDevEnvironment()) {
                console.log('[Cropper] Direct load succeeded')
              }
              this.imageNaturalSize = { width: imageEl.naturalWidth, height: imageEl.naturalHeight }
              this.imageLoaded = true
              this.waitForModalRender(() => {
                this.calculateInitialZoom()
                this.centerImage()
                this.updateImageTransform()
                setTimeout(() => this.syncZoomSlider(), 100)
              })
            }
            imageEl.onerror = () => {
              if (this.isDevEnvironment()) {
                console.error('[Cropper] All load attempts failed')
              }
              this.closeModal()
              alert('Failed to load image for cropping. The image may be inaccessible.')
            }
            imageEl.src = imageUrl
          } else {
            this.closeModal()
            alert('Failed to load image for cropping.')
          }
        }
        retryImg.src = imageUrl
        return
      }
      
      this.closeModal()
      alert('Failed to load image for cropping. Please try again.')
    }

    img.onload = handleSuccess
    img.onerror = handleError
    
    // First try with CORS (needed for canvas operations like thumbnail generation)
    img.crossOrigin = 'anonymous'
    img.src = imageUrl
  }
  
  // Wait for the modal to be fully rendered before executing callback
  waitForModalRender(callback) {
    // Use double requestAnimationFrame to ensure layout is complete
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        // Additional small delay for CSS transitions
        setTimeout(() => {
          callback()
          
          // Double-check and recalculate after another frame if needed
          // This handles cases where the first calculation used stale values
          requestAnimationFrame(() => {
            const viewportSize = this.viewportSize()
            const scaledWidth = this.imageNaturalSize.width * this.zoom
            const scaledHeight = this.imageNaturalSize.height * this.zoom
            
            // If the image doesn't cover the viewport, recalculate
            if (scaledWidth < viewportSize || scaledHeight < viewportSize) {
              if (this.isDevEnvironment()) {
                console.log('Image not covering viewport, recalculating...', {
                  viewportSize, scaledWidth, scaledHeight, zoom: this.zoom
                })
              }
              this.calculateInitialZoom()
              this.centerImage()
              this.updateImageTransform()
            }
          })
        }, 50)
      })
    })
  }

  calculateInitialZoom() {
    // Calculate minimum zoom so image covers the viewport
    const viewportSize = this.viewportSize()
    const { width, height } = this.imageNaturalSize
    
    if (this.isDevEnvironment()) {
      console.log('[Cropper] calculateInitialZoom:', { viewportSize, width, height })
    }
    
    // Guard against invalid dimensions
    if (width <= 0 || height <= 0 || viewportSize <= 0) {
      console.warn('Invalid dimensions for zoom calculation:', { width, height, viewportSize })
      this.minZoom = 1
      this.maxZoom = 3
      this.zoom = 1
      return
    }

    // Find the zoom level that makes the smaller dimension fit the viewport
    // For a square viewport, we need the image to COVER the viewport
    // So we use the larger zoom factor (to ensure full coverage)
    const zoomToFitWidth = viewportSize / width
    const zoomToFitHeight = viewportSize / height

    // We want the image to at least cover the viewport
    // Use Math.max so the image fills the viewport completely
    // Add a tiny epsilon to avoid 1px gaps from floating point rounding.
    this.minZoom = Math.max(zoomToFitWidth, zoomToFitHeight) * 1.005
    
    // Max zoom allows zooming in up to 3x the minimum cover zoom
    this.maxZoom = this.minZoom * this.maxZoomValue
    
    // Start at minimum zoom (image just covers viewport)
    this.zoom = this.minZoom

    if (this.isDevEnvironment()) {
      console.log('[Cropper] Zoom calculated:', {
        zoomToFitWidth,
        zoomToFitHeight,
        minZoom: this.minZoom,
        maxZoom: this.maxZoom,
        zoom: this.zoom
      })
    }

    const zoomSlider = this.getZoomSlider()
    if (zoomSlider) {
      // Update slider range to match calculated values
      // Use setAttribute to ensure the HTML attributes are updated, not just JS properties
      zoomSlider.setAttribute('min', this.minZoom.toString())
      zoomSlider.setAttribute('max', this.maxZoom.toString())
      zoomSlider.setAttribute('step', ((this.maxZoom - this.minZoom) / 100).toString())
      
      // Also set the JS properties for immediate effect
      zoomSlider.min = this.minZoom
      zoomSlider.max = this.maxZoom
      zoomSlider.step = (this.maxZoom - this.minZoom) / 100
      
      // Set value after min/max are updated
      zoomSlider.value = this.zoom
      
      if (this.isDevEnvironment()) {
        console.log('Zoom slider updated:', { 
          min: zoomSlider.min, 
          max: zoomSlider.max, 
          value: zoomSlider.value,
          actualValue: parseFloat(zoomSlider.value)
        })
      }
    }
  }

  centerImage() {
    // Set center to the middle of the image (in image pixels)
    this.center = {
      x: this.imageNaturalSize.width / 2,
      y: this.imageNaturalSize.height / 2
    }
  }

  resetState() {
    this.zoom = 1
    this.minZoom = 1
    this.maxZoom = 3
    this.center = { x: 0, y: 0 }
    this.position = { x: 0, y: 0 }
    this.isDragging = false
    this.imageLoaded = false

    const zoomSlider = this.getZoomSlider()
    if (zoomSlider) {
      zoomSlider.value = 1
    }
    
    // Reset image element
    const imageEl = this.getImage()
    if (imageEl) {
      imageEl.src = ''
      imageEl.style.width = ''
      imageEl.style.height = ''
      imageEl.style.transform = ''
    }
  }

  updateImageTransform() {
    const imageEl = this.getImage()
    if (!imageEl) return

    // Ensure center stays valid for current zoom before rendering.
    this.constrainCenter()

    const viewportSize = this.viewportSize()
    const viewportCenter = viewportSize / 2

    // Render model:
    // screenX = position.x + imgX * zoom
    // We want img center (this.center) to land at viewport center.
    this.position = {
      x: viewportCenter - this.center.x * this.zoom,
      y: viewportCenter - this.center.y * this.zoom
    }

    const scaledWidth = this.imageNaturalSize.width * this.zoom
    const scaledHeight = this.imageNaturalSize.height * this.zoom

    if (this.isDevEnvironment()) {
      console.log('[Cropper] updateImageTransform:', {
        viewportSize,
        scaledWidth,
        scaledHeight,
        zoom: this.zoom
      })
    }

    // Apply the transform styles
    imageEl.style.width = `${scaledWidth}px`
    imageEl.style.height = `${scaledHeight}px`
    imageEl.style.transform = `translate(${this.position.x}px, ${this.position.y}px)`
    
    // Ensure styles are applied immediately
    imageEl.style.willChange = 'transform'
    imageEl.style.maxWidth = 'none'  // Override any CSS max-width
    imageEl.style.maxHeight = 'none' // Override any CSS max-height
    
    // Force a reflow to ensure styles are applied
    // eslint-disable-next-line no-unused-expressions
    imageEl.offsetHeight
    
    if (this.isDevEnvironment()) {
      console.log('[Cropper] Applied styles:', {
        width: imageEl.style.width,
        height: imageEl.style.height,
        transform: imageEl.style.transform
      })
    }
  }

  constrainCenter() {
    // Clamp center in image coordinates so the viewport is always covered.
    // Visible half-size in image pixels:
    const half = this.viewportSize() / (2 * this.zoom)

    const minX = half
    const maxX = this.imageNaturalSize.width - half
    const minY = half
    const maxY = this.imageNaturalSize.height - half

    // Guard: if rounding/edge cases make max < min, fall back to image center.
    if (maxX < minX) {
      this.center.x = this.imageNaturalSize.width / 2
    } else {
      this.center.x = Math.min(maxX, Math.max(minX, this.center.x))
    }

    if (maxY < minY) {
      this.center.y = this.imageNaturalSize.height / 2
    } else {
      this.center.y = Math.min(maxY, Math.max(minY, this.center.y))
    }
  }

  // Mouse drag handlers
  startDrag(event) {
    if (!this.imageLoaded) return
    event.preventDefault()

    this.isDragging = true
    this.dragStart = {
      x: event.clientX,
      y: event.clientY,
      centerX: this.center.x,
      centerY: this.center.y
    }

    document.addEventListener('mousemove', this.handleMouseMove)
    document.addEventListener('mouseup', this.handleMouseUp)
  }

  handleMouseMove(event) {
    if (!this.isDragging) return

    const dx = event.clientX - this.dragStart.x
    const dy = event.clientY - this.dragStart.y

    this.center = {
      x: this.dragStart.centerX - dx / this.zoom,
      y: this.dragStart.centerY - dy / this.zoom
    }

    this.constrainCenter()
    this.updateImageTransform()
  }

  handleMouseUp() {
    this.isDragging = false
    this.removeGlobalListeners()
  }

  // Touch drag handlers
  startTouchDrag(event) {
    if (!this.imageLoaded || event.touches.length !== 1) return
    event.preventDefault()

    const touch = event.touches[0]
    this.isDragging = true
    this.dragStart = {
      x: touch.clientX,
      y: touch.clientY,
      centerX: this.center.x,
      centerY: this.center.y
    }

    document.addEventListener('touchmove', this.handleTouchMove, { passive: false })
    document.addEventListener('touchend', this.handleTouchEnd)
  }

  handleTouchMove(event) {
    if (!this.isDragging || event.touches.length !== 1) return
    event.preventDefault()

    const touch = event.touches[0]
    const dx = touch.clientX - this.dragStart.x
    const dy = touch.clientY - this.dragStart.y

    this.center = {
      x: this.dragStart.centerX - dx / this.zoom,
      y: this.dragStart.centerY - dy / this.zoom
    }

    this.constrainCenter()
    this.updateImageTransform()
  }

  handleTouchEnd() {
    this.isDragging = false
    this.removeGlobalListeners()
  }

  removeGlobalListeners() {
    document.removeEventListener('mousemove', this.handleMouseMove)
    document.removeEventListener('mouseup', this.handleMouseUp)
    document.removeEventListener('touchmove', this.handleTouchMove)
    document.removeEventListener('touchend', this.handleTouchEnd)
  }

  // Zoom handlers
  zoomChange(event) {
    if (!this.imageLoaded) return

    const newZoom = parseFloat(event.target.value)
    this.setZoom(newZoom)
  }

  zoomIn(event) {
    event.preventDefault()
    const step = (this.maxZoom - this.minZoom) / 10
    this.setZoom(this.zoom + step)
  }

  zoomOut(event) {
    event.preventDefault()
    const step = (this.maxZoom - this.minZoom) / 10
    this.setZoom(this.zoom - step)
  }

  setZoom(newZoom) {
    this.zoom = Math.max(this.minZoom, Math.min(this.maxZoom, newZoom))

    this.syncZoomSlider()
    this.constrainCenter()
    this.updateImageTransform()
  }
  
  // Forcefully sync the zoom slider with current state
  syncZoomSlider() {
    const zoomSlider = this.getZoomSlider()
    if (!zoomSlider) return
    
    // Update slider attributes to match our calculated values
    const minStr = this.minZoom.toFixed(4)
    const maxStr = this.maxZoom.toFixed(4)
    const valueStr = this.zoom.toFixed(4)
    const stepStr = ((this.maxZoom - this.minZoom) / 100).toFixed(6)
    
    // Set attributes
    zoomSlider.setAttribute('min', minStr)
    zoomSlider.setAttribute('max', maxStr)
    zoomSlider.setAttribute('step', stepStr)
    
    // Set properties
    zoomSlider.min = minStr
    zoomSlider.max = maxStr
    zoomSlider.step = stepStr
    zoomSlider.value = valueStr
    
    if (this.isDevEnvironment()) {
      console.log('syncZoomSlider:', {
        min: zoomSlider.min,
        max: zoomSlider.max,
        value: zoomSlider.value,
        step: zoomSlider.step
      })
    }
  }

  // Apply crop - handles both server submission and form field modes
  async applyCrop(event) {
    event.preventDefault()

    if (!this.imageLoaded) return

    const button = event.currentTarget
    const originalText = button.textContent

    // Calculate crop coordinates in original image pixels
    const viewportSize = this.viewportSize()

    const cropSize = viewportSize / this.zoom
    const cropX = this.center.x - cropSize / 2
    const cropY = this.center.y - cropSize / 2

    const cropData = {
      x: Math.round(cropX),
      y: Math.round(cropY),
      width: Math.round(cropSize),
      height: Math.round(cropSize),
      rotate: 0,
      scaleX: 1,
      scaleY: 1
    }

    if (this.isDevEnvironment()) {
      console.log('Applying crop:', cropData, 'Mode:', this.isFileUploadMode ? 'file' : 'server')
    }

    // FILE UPLOAD MODE: Store crop data in hidden field
    if (this.isFileUploadMode) {
      // Save crop data to hidden field
      if (this.hasCropDataTarget) {
        this.cropDataTarget.value = JSON.stringify(cropData)
      }

      // Generate and show thumbnail preview
      this.generateThumbnail()

      // Show the thumbnail container
      if (this.hasThumbnailTarget) {
        this.thumbnailTarget.classList.remove('hidden')
      }

      this.closeModal()
      return
    }

    // SERVER MODE: Send crop data to server endpoint
    if (!this.currentCropUrl) {
      if (this.isDevEnvironment()) {
        console.error('No crop URL specified for server mode')
      }
      return
    }

    try {
      button.disabled = true
      button.textContent = 'Applying...'

      const response = await fetch(this.currentCropUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'X-CSRF-Token': this.getCSRFToken()
        },
        body: JSON.stringify({ crop_data: cropData })
      })

      if (response.ok) {
        this.closeModal()
        window.location.reload()
      } else {
        const error = await response.json()
        throw new Error(error.error || 'Failed to crop image')
      }
    } catch (error) {
      if (this.isDevEnvironment()) {
        console.error('Crop failed:', error)
      }
      alert(error.message || 'Failed to apply crop. Please try again.')
    } finally {
      button.disabled = false
      button.textContent = originalText
    }
  }

  // Generate thumbnail preview from current crop state
  generateThumbnail() {
    if (!this.hasThumbnailImageTarget) return

    const imageEl = this.getImage()
    if (!imageEl || !imageEl.src) return

    // Create a canvas to draw the cropped preview
    const canvas = document.createElement('canvas')
    const ctx = canvas.getContext('2d')
    
    // Thumbnail size
    const thumbSize = 200
    canvas.width = thumbSize
    canvas.height = thumbSize

    // Calculate crop region in original image coordinates
    const viewportSize = this.viewportSize()
    const cropSize = viewportSize / this.zoom
    const cropX = this.center.x - cropSize / 2
    const cropY = this.center.y - cropSize / 2

    // Create a temporary image to draw from
    const tempImg = new Image()
    tempImg.crossOrigin = 'anonymous'
    
    tempImg.onload = () => {
      // Draw the cropped region
      ctx.drawImage(
        tempImg,
        cropX, cropY, cropSize, cropSize,  // Source rectangle
        0, 0, thumbSize, thumbSize          // Destination rectangle
      )

      // Set thumbnail source
      const thumbnailUrl = canvas.toDataURL('image/jpeg', 0.8)
      this.thumbnailImageTarget.src = thumbnailUrl
    }

    tempImg.onerror = () => {
      // Fallback: just use the original image URL
      this.thumbnailImageTarget.src = imageEl.src
    }

    tempImg.src = imageEl.src
  }

  getCSRFToken() {
    const meta = document.querySelector('meta[name="csrf-token"]')
    return meta ? meta.content : ''
  }

  cancelCrop(event) {
    if (event) {
      event.preventDefault()
    }
    
    // For file upload mode, also clear the file input
    if (this.isFileUploadMode && this.hasFileInputTarget) {
      this.fileInputTarget.value = ''
      this.currentFile = null
      
      // Clear crop data
      if (this.hasCropDataTarget) {
        this.cropDataTarget.value = ''
      }
    }
    
    this.closeModal()
  }

  closeModal() {
    const modal = this.getModal()
    if (modal) {
      modal.classList.add('hidden')
    }
    document.body.classList.remove('overflow-hidden')
    this.currentCropUrl = null
    this.isFileUploadMode = false
    this.removeGlobalListeners()
    this.resetState()
    
    // Clean up object URL if from file upload
    if (this.currentImageUrl) {
      URL.revokeObjectURL(this.currentImageUrl)
      this.currentImageUrl = null
    }
  }
  
  // Cancel crop for file upload mode - also clears the file input
  cancelCropAndClearFile(event) {
    if (event) {
      event.preventDefault()
    }
    
    // Clear file input if in file upload mode
    if (this.isFileUploadMode && this.hasFileInputTarget) {
      this.fileInputTarget.value = ''
      this.currentFile = null
      
      // Clear crop data
      if (this.hasCropDataTarget) {
        this.cropDataTarget.value = ''
      }
      
      // Hide thumbnail
      if (this.hasThumbnailTarget) {
        this.thumbnailTarget.classList.add('hidden')
      }
    }
    
    this.closeModal()
  }

  stopPropagation(event) {
    event.stopPropagation()
  }
}
