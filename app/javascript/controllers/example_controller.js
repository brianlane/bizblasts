import { Controller } from "@hotwired/stimulus"

// Example controller to demonstrate auto-discovery
// This controller will be automatically discovered and registered
export default class extends Controller {
  static targets = ["output", "input"]
  static values = { message: String }

  connect() {
    if (this.hasOutputTarget) {
      this.outputTarget.textContent = "Example controller connected! 🎉"
    }
    
    // Log in development mode
    const isDev = (typeof process !== 'undefined' && process.env && process.env.NODE_ENV === 'development') ||
                  (typeof window !== 'undefined' && window.location && 
                   (window.location.hostname.includes('lvh.me') || window.location.hostname === 'localhost'));
    
    if (isDev) {
      console.log("🎯 Example controller connected via auto-discovery")
    }
  }

  greet() {
    const name = this.hasInputTarget ? this.inputTarget.value : "World"
    const message = this.messageValue || `Hello, ${name}!`
    
    if (this.hasOutputTarget) {
      this.outputTarget.textContent = message
    }
  }

  clear() {
    if (this.hasInputTarget) {
      this.inputTarget.value = ""
    }
    if (this.hasOutputTarget) {
      this.outputTarget.textContent = ""
    }
  }

  // Example of using Stimulus values
  updateMessage(event) {
    this.messageValue = event.target.value
  }
} 