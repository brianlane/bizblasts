// app/javascript/controllers/qr_payment_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modal", "content", "status", "success"]
  static values = { invoiceId: Number }
  
  connect() {
    this.pollingInterval = null
  }
  
  disconnect() {
    this.stopPolling()
  }
  
  showModal(event) {
    event.preventDefault()
    const invoiceId = event.currentTarget.dataset.qrPaymentInvoiceIdValue
    
    if (!invoiceId) {
      console.error("No invoice ID provided for QR payment")
      return
    }
    
    this.invoiceIdValue = parseInt(invoiceId)
    this.loadQRCode()
  }
  
  closeModal() {
    this.modalTarget.classList.add("hidden")
    this.stopPolling()
  }
  
  async loadQRCode() {
    try {
      const response = await fetch(`/manage/invoices/${this.invoiceIdValue}/qr_payment`, {
        headers: {
          'Accept': 'text/html'
        }
      })
      
      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`)
      }
      
      const html = await response.text()
      this.contentTarget.innerHTML = html
      this.modalTarget.classList.remove("hidden")
      
      // Start polling for payment status
      this.startPolling()
      
    } catch (error) {
      console.error("Error loading QR code:", error)
      this.contentTarget.innerHTML = `
        <div class="text-center text-red-600">
          <p class="font-medium">Error loading QR code</p>
          <p class="text-sm mt-2">Please try again in a moment.</p>
        </div>
      `
      this.modalTarget.classList.remove("hidden")
    }
  }
  
  startPolling() {
    // Poll every 5 seconds for payment status
    this.pollingInterval = setInterval(() => {
      this.checkPaymentStatus()
    }, 5000)
  }
  
  stopPolling() {
    if (this.pollingInterval) {
      clearInterval(this.pollingInterval)
      this.pollingInterval = null
    }
  }
  
  async checkPaymentStatus() {
    try {
      const response = await fetch(`/manage/invoices/${this.invoiceIdValue}/payment_status`, {
        headers: {
          'Accept': 'application/json'
        }
      })
      
      if (!response.ok) {
        console.error(`Payment status check failed: ${response.status}`)
        return
      }
      
      const data = await response.json()
      
      if (data.paid) {
        // Payment successful!
        this.handlePaymentSuccess()
      } else {
        // Update status display if needed
        this.updateStatusDisplay(data)
      }
      
    } catch (error) {
      console.error("Error checking payment status:", error)
    }
  }
  
  handlePaymentSuccess() {
    this.stopPolling()
    
    // Hide the waiting status
    if (this.hasStatusTarget) {
      this.statusTarget.classList.add("hidden")
    }
    
    // Show success message
    if (this.hasSuccessTarget) {
      this.successTarget.classList.remove("hidden")
    }
    
    // Auto-close modal and refresh page after 3 seconds
    setTimeout(() => {
      this.closeModal()
      window.location.reload()
    }, 3000)
  }
  
  updateStatusDisplay(statusData) {
    // Update the status display with current payment information
    if (this.hasStatusTarget && statusData.balance_due !== undefined) {
      const balanceDue = parseFloat(statusData.balance_due)
      if (balanceDue > 0) {
        const formattedBalance = new Intl.NumberFormat('en-US', {
          style: 'currency',
          currency: 'USD'
        }).format(balanceDue)
        
        this.statusTarget.innerHTML = `
          <div class="flex items-center justify-center">
            <div class="animate-spin rounded-full h-4 w-4 border-b-2 border-blue-600 mr-2"></div>
            <span class="text-sm text-gray-600">Waiting for payment... (${formattedBalance} remaining)</span>
          </div>
        `
      }
    }
  }
}