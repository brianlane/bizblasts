import { Controller } from "@hotwired/stimulus"
import SignaturePad from "signature_pad"

// Reusable signature pad controller for capturing customer signatures
// Can be used for estimates, contracts, and other documents requiring signatures
export default class extends Controller {
  static targets = [
    "canvas",
    "signatureData",
    "signatureName",
    "clearButton",
    "submitButton",
    "validationMessage"
  ]

  static values = {
    required: { type: Boolean, default: true },
    backgroundColor: { type: String, default: "rgb(255, 255, 255)" },
    penColor: { type: String, default: "rgb(0, 0, 0)" }
  }

  connect() {
    console.log("SignaturePad controller connected")
    this.initializeSignaturePad()
    this.validateSignature()
  }

  disconnect() {
    if (this.signaturePad) {
      this.signaturePad.off()
    }
    window.removeEventListener('resize', this.resizeCanvas.bind(this))
  }

  initializeSignaturePad() {
    if (!this.hasCanvasTarget) return

    const canvas = this.canvasTarget

    // Set canvas dimensions
    this.resizeCanvas()

    // Initialize Signature Pad
    this.signaturePad = new SignaturePad(canvas, {
      backgroundColor: this.backgroundColorValue,
      penColor: this.penColorValue,
      minWidth: 1,
      maxWidth: 2.5
    })

    // Listen for signature changes
    this.signaturePad.addEventListener("endStroke", () => {
      this.validateSignature()
      this.updateSignatureData()
    })

    // Handle window resize
    window.addEventListener('resize', this.resizeCanvas.bind(this))
  }

  resizeCanvas() {
    if (!this.hasCanvasTarget) return

    const canvas = this.canvasTarget
    const ratio = Math.max(window.devicePixelRatio || 1, 1)
    const container = canvas.parentElement

    // Store signature data before resize
    const data = this.signaturePad?.toData()

    // Set canvas size based on container
    canvas.width = container.offsetWidth * ratio
    canvas.height = (container.offsetHeight || 150) * ratio
    canvas.style.width = `${container.offsetWidth}px`
    canvas.style.height = `${container.offsetHeight || 150}px`

    canvas.getContext("2d").scale(ratio, ratio)

    // Restore signature data if available
    if (this.signaturePad) {
      this.signaturePad.clear()
      if (data) {
        this.signaturePad.fromData(data)
      }
    }
  }

  clearSignature(event) {
    event?.preventDefault()
    if (this.signaturePad) {
      this.signaturePad.clear()
      if (this.hasSignatureDataTarget) {
        this.signatureDataTarget.value = ""
      }
      this.validateSignature()
    }
  }

  validateSignature() {
    const hasSignature = this.signaturePad && !this.signaturePad.isEmpty()
    const hasName = this.hasSignatureNameTarget && this.signatureNameTarget.value.trim().length > 0
    const isValid = (!this.requiredValue) || (hasSignature && hasName)

    // Update submit button state
    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.disabled = !isValid
      if (isValid) {
        this.submitButtonTarget.classList.remove('opacity-50', 'cursor-not-allowed')
      } else {
        this.submitButtonTarget.classList.add('opacity-50', 'cursor-not-allowed')
      }
    }

    // Update validation message
    if (this.hasValidationMessageTarget) {
      if (!hasSignature && !hasName) {
        this.validationMessageTarget.textContent = "Please sign and enter your name"
        this.validationMessageTarget.classList.remove('hidden')
      } else if (!hasSignature) {
        this.validationMessageTarget.textContent = "Please provide your signature"
        this.validationMessageTarget.classList.remove('hidden')
      } else if (!hasName) {
        this.validationMessageTarget.textContent = "Please enter your name"
        this.validationMessageTarget.classList.remove('hidden')
      } else {
        this.validationMessageTarget.textContent = ""
        this.validationMessageTarget.classList.add('hidden')
      }
    }

    return isValid
  }

  updateSignatureData() {
    if (this.signaturePad && this.hasSignatureDataTarget) {
      if (this.signaturePad.isEmpty()) {
        this.signatureDataTarget.value = ""
      } else {
        // Get signature as PNG data URL
        this.signatureDataTarget.value = this.signaturePad.toDataURL("image/png")
      }
    }
  }

  nameChanged() {
    this.validateSignature()
  }

  // Called before form submission to ensure signature data is captured
  prepareSubmission(event) {
    this.updateSignatureData()

    // Final validation
    if (this.requiredValue && !this.validateSignature()) {
      event?.preventDefault()

      // Show alert if validation message target doesn't exist
      if (!this.hasValidationMessageTarget) {
        if (this.signaturePad?.isEmpty()) {
          alert("Please provide your signature before submitting.")
        } else if (this.hasSignatureNameTarget && !this.signatureNameTarget.value.trim()) {
          alert("Please enter your name before submitting.")
        }
      }

      return false
    }

    return true
  }

  // Get signature data as PNG
  getSignatureData() {
    if (this.signaturePad && !this.signaturePad.isEmpty()) {
      return this.signaturePad.toDataURL("image/png")
    }
    return null
  }

  // Check if signature pad has a signature
  hasSignature() {
    return this.signaturePad && !this.signaturePad.isEmpty()
  }

  // Check if name field has a value
  hasName() {
    return this.hasSignatureNameTarget && this.signatureNameTarget.value.trim().length > 0
  }
}

