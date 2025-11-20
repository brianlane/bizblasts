import { Controller } from "@hotwired/stimulus"

// Gallery carousel controller for featured photos
export default class extends Controller {
  static targets = ["track", "slide", "indicator"]

  connect() {
    this.currentIndex = 0
    this.totalSlides = this.slideTargets.length

    if (this.totalSlides > 1) {
      this.startAutoplay()
    }
  }

  disconnect() {
    this.stopAutoplay()
  }

  next() {
    this.goToSlide((this.currentIndex + 1) % this.totalSlides)
  }

  prev() {
    this.goToSlide((this.currentIndex - 1 + this.totalSlides) % this.totalSlides)
  }

  goTo(event) {
    const index = parseInt(event.currentTarget.dataset.index)
    this.goToSlide(index)
  }

  goToSlide(index) {
    this.currentIndex = index
    const offset = -100 * index
    this.trackTarget.style.transform = `translateX(${offset}%)`

    // Update indicators
    if (this.hasIndicatorTarget) {
      this.indicatorTargets.forEach((indicator, i) => {
        if (i === index) {
          indicator.classList.add("accent-bg", "w-8")
          indicator.classList.remove("bg-gray-300")
        } else {
          indicator.classList.remove("accent-bg", "w-8")
          indicator.classList.add("bg-gray-300")
        }
      })
    }

    // Reset autoplay timer
    this.stopAutoplay()
    this.startAutoplay()
  }

  startAutoplay() {
    if (this.totalSlides > 1) {
      this.autoplayTimer = setInterval(() => {
        this.next()
      }, 5000) // Change slide every 5 seconds
    }
  }

  stopAutoplay() {
    if (this.autoplayTimer) {
      clearInterval(this.autoplayTimer)
      this.autoplayTimer = null
    }
  }
}
