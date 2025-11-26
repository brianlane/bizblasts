import { Controller } from "@hotwired/stimulus"

// Hero video controller for autoplay management
export default class extends Controller {
  connect() {
    // Fix for Turbo Drive: force video to reload when restored from cache
    if (this.element.readyState === 0) {
      this.element.load()
    }
    
    // Check if video is already ready to play
    if (this.element.readyState >= 3) {
      this.ensureVideoPlays()
    } else {
      // Wait for video to be ready
      this.element.addEventListener('canplay', () => this.ensureVideoPlays(), { once: true })
      this.element.addEventListener('loadeddata', () => this.ensureVideoPlays(), { once: true })
    }
    
    this.observeVisibility()
  }

  disconnect() {
    if (this.observer) {
      this.observer.disconnect()
    }
    this.playAttempted = false
  }

  ensureVideoPlays() {
    if (this.playAttempted) return
    this.playAttempted = true
    
    // Ensure video is muted (required for autoplay in most browsers)
    this.element.muted = true
    
    const playPromise = this.element.play()
    if (playPromise !== undefined) {
      playPromise.catch(() => {
        // Retry once with muted explicitly set
        this.element.muted = true
        this.element.play().catch(() => {})
      })
    }
  }

  observeVisibility() {
    if ('IntersectionObserver' in window) {
      this.observer = new IntersectionObserver((entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            if (this.element.paused) {
              this.element.play().catch(() => {})
            }
          } else {
            this.element.pause()
          }
        })
      }, { threshold: 0.25 })

      this.observer.observe(this.element)
    }
  }
}
