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
    this.boundResizeHandler = this.resizeCanvas.bind(this)
    this.initializeSignaturePad()
    this.validateSignature()
  }

  disconnect() {
    if (this.signaturePad) {
      this.signaturePad.off()
    }
    if (this.boundResizeHandler) {
      window.removeEventListener('resize', this.boundResizeHandler)
    }
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
    window.addEventListener('resize', this.boundResizeHandler)
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

  // Handle optional item checkbox toggle - recalculate totals dynamically
  toggleOptionalItem(event) {
    const checkbox = event.target
    const row = checkbox.closest('[data-estimate-signature-target="optionalItem"]')

    if (!row) return

    // Get item amounts from data attributes
    const itemSubtotal = parseFloat(row.dataset.subtotal || 0)
    const itemTaxes = parseFloat(row.dataset.taxes || 0)

    // Get base amounts (required items only)
    const totalDisplay = document.getElementById('estimate-total-display')
    if (!totalDisplay) return

    const baseSubtotal = parseFloat(totalDisplay.dataset.baseSubtotal || 0)
    const baseTaxes = parseFloat(totalDisplay.dataset.baseTaxes || 0)

    // Calculate totals for all selected optional items
    let optionalSubtotal = 0
    let optionalTaxes = 0

    document.querySelectorAll('[data-estimate-signature-target="optionalItemCheckbox"]:checked').forEach(cb => {
      const cbRow = cb.closest('[data-estimate-signature-target="optionalItem"]')
      if (cbRow) {
        optionalSubtotal += parseFloat(cbRow.dataset.subtotal || 0)
        optionalTaxes += parseFloat(cbRow.dataset.taxes || 0)
      }
    })

    // Calculate final totals
    const finalSubtotal = baseSubtotal + optionalSubtotal
    const finalTaxes = baseTaxes + optionalTaxes
    const finalTotal = finalSubtotal + finalTaxes

    // Update display
    const subtotalEl = document.getElementById('subtotal-amount')
    const taxesEl = document.getElementById('taxes-amount')
    const totalEl = document.getElementById('total-amount')

    if (subtotalEl) {
      subtotalEl.textContent = this.formatCurrency(finalSubtotal)
    }
    if (taxesEl) {
      taxesEl.textContent = this.formatCurrency(finalTaxes)
    }
    if (totalEl) {
      totalEl.textContent = this.formatCurrency(finalTotal)
    }

    // Toggle row styling
    if (checkbox.checked) {
      row.classList.remove('bg-gray-50', 'line-through', 'text-gray-400')
    } else {
      row.classList.add('bg-gray-50', 'line-through', 'text-gray-400')
    }
  }

  // Format number as currency (USD)
  formatCurrency(amount) {
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: 'USD'
    }).format(amount)
  }
}

