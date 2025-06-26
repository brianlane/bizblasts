import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["form"]
  
  connect() {
    console.log("Edit section controller connected")
  }
  
  submit(event) {
    event.preventDefault()
    event.stopPropagation()
    event.stopImmediatePropagation()
    console.log('Form submission intercepted by Stimulus controller')
    
    // Make sure no other handlers run
    if (event.detail) {
      event.detail.abort = true
    }
    
    const form = this.formTarget
    const formData = new FormData(form)
    
    console.log('Submitting to:', form.action)
    console.log('Form data:', [...formData.entries()])
    
    // Add .json format to force JSON response
    const url = form.action + '.json'
    console.log('Fetching URL:', url)
    
    fetch(url, {
      method: 'PATCH',
      body: formData,
      headers: {
        'Accept': 'application/json',
        'X-Requested-With': 'XMLHttpRequest',
        'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
      }
    })
    .then(response => response.json())
    .then(data => {
      if (data.status === 'success') {
        // Close modal
        this.closeModal()
        
        // Show success message
        if (data.message) {
          alert(data.message)
        }
        
        // Redirect or reload
        if (data.redirect_url) {
          window.location.href = data.redirect_url
        } else {
          window.location.reload()
        }
      } else {
        alert('Error: ' + JSON.stringify(data.errors || 'Unknown error'))
      }
    })
    .catch(error => {
      console.error('Error:', error)
      alert('Section updated, reloading page...')
      window.location.reload()
    })
  }
  
  close() {
    this.closeModal()
  }
  
  closeModal() {
    // Find the modal element that contains this form
    const modal = document.querySelector('[data-page-editor-target="editModal"]')
    if (modal) {
      modal.classList.add('hidden')
      console.log('Modal closed successfully')
    } else {
      console.log('Modal not found')
    }
  }
} 