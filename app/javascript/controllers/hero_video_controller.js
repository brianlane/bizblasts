import { Controller } from "@hotwired/stimulus"

// Hero video controller for autoplay management
export default class extends Controller {
  connect() {
    this.ensureVideoPlays()
    this.observeVisibility()
  }

  disconnect() {
    if (this.observer) {
      this.observer.disconnect()
    }
  }

  ensureVideoPlays() {
    // Ensure video plays (browsers sometimes block autoplay)
    const playPromise = this.element.play()

    if (playPromise !== undefined) {
      playPromise
        .then(() => {
          // Autoplay started successfully
          console.log("Hero video autoplay started")
        })
        .catch((error) => {
          // Autoplay was prevented, try muted
          console.log("Autoplay prevented, ensuring muted:", error)
          this.element.muted = true
          this.element.play()
        })
    }
  }

  observeVisibility() {
    // Pause video when not visible to save bandwidth
    if ('IntersectionObserver' in window) {
      this.observer = new IntersectionObserver((entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            this.element.play()
          } else {
            this.element.pause()
          }
        })
      }, { threshold: 0.25 })

      this.observer.observe(this.element)
    }
  }
}
