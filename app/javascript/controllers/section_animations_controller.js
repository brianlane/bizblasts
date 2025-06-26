import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["section"]
  
  connect() {
    console.log("Section animations controller connected")
    this.setupIntersectionObserver()
    this.observeSections()
  }
  
  disconnect() {
    if (this.observer) {
      this.observer.disconnect()
    }
  }
  
  setupIntersectionObserver() {
    const options = {
      root: null, // Use viewport as root
      rootMargin: '0px 0px -50px 0px', // Trigger when section is 50px into viewport
      threshold: 0.1 // Trigger when 10% of section is visible
    }
    
    this.observer = new IntersectionObserver((entries) => {
      entries.forEach(entry => {
        if (entry.isIntersecting) {
          this.animateSection(entry.target)
        }
      })
    }, options)
  }
  
  observeSections() {
    // Find all sections with animation classes
    const animatedSections = document.querySelectorAll('.page-section[class*="animate-"]')
    
    animatedSections.forEach(section => {
      this.observer.observe(section)
    })
  }
  
  animateSection(section) {
    // Add the 'in-view' class to trigger animation
    section.classList.add('in-view')
    
    // Stop observing this section once animated
    this.observer.unobserve(section)
  }
} 