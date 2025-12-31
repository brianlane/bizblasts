import { Controller } from "@hotwired/stimulus"

// Period selector controller for analytics pages
// Uses the standard dropdown component and navigates when a period is selected
export default class extends Controller {
  static targets = ["button", "menu", "option"]
  static values = { 
    basePath: String,
    currentPeriod: String
  }
  
  connect() {
    this.isOpen = false
    this.setupOutsideClickListener()
  }
  
  disconnect() {
    this.removeOutsideClickListener()
  }
  
  toggle(event) {
    event.preventDefault()
    event.stopPropagation()
    
    this.isOpen ? this.close() : this.open()
  }
  
  open() {
    this.menuTarget.classList.remove('hidden')
    this.buttonTarget.setAttribute('aria-expanded', 'true')
    
    // Rotate arrow if present
    const arrow = this.buttonTarget.querySelector('svg')
    if (arrow) arrow.classList.add('rotate-180')
    
    // Use fixed positioning to escape overflow:hidden containers
    this.positionDropdownFixed()
    
    this.isOpen = true
  }
  
  positionDropdownFixed() {
    const buttonRect = this.buttonTarget.getBoundingClientRect()
    const menu = this.menuTarget
    
    // Use fixed positioning to escape overflow:hidden parent containers
    menu.style.position = 'fixed'
    menu.style.left = `${buttonRect.left}px`
    menu.style.width = `${Math.max(buttonRect.width, 160)}px`
    
    // Get menu dimensions after making it visible
    const menuHeight = menu.scrollHeight
    const viewportHeight = window.innerHeight
    const spaceBelow = viewportHeight - buttonRect.bottom
    const spaceAbove = buttonRect.top
    
    // Position below or above depending on available space
    if (spaceBelow >= menuHeight || spaceBelow >= spaceAbove) {
      // Position below the button
      menu.style.top = `${buttonRect.bottom + 4}px`
      menu.style.bottom = 'auto'
    } else {
      // Position above the button
      menu.style.bottom = `${viewportHeight - buttonRect.top + 4}px`
      menu.style.top = 'auto'
    }
    
    // Ensure menu doesn't go off the right edge of viewport
    const menuRect = menu.getBoundingClientRect()
    if (menuRect.right > window.innerWidth - 16) {
      menu.style.left = 'auto'
      menu.style.right = '16px'
    }
    
    // Ensure menu doesn't go off the left edge
    if (menuRect.left < 16) {
      menu.style.left = '16px'
      menu.style.right = 'auto'
    }
  }
  
  close() {
    this.menuTarget.classList.add('hidden')
    this.buttonTarget.setAttribute('aria-expanded', 'false')
    
    // Reset arrow rotation
    const arrow = this.buttonTarget.querySelector('svg')
    if (arrow) arrow.classList.remove('rotate-180')
    
    // Reset positioning styles
    this.menuTarget.style.position = ''
    this.menuTarget.style.top = ''
    this.menuTarget.style.bottom = ''
    this.menuTarget.style.left = ''
    this.menuTarget.style.right = ''
    this.menuTarget.style.width = ''
    
    this.isOpen = false
  }
  
  select(event) {
    event.preventDefault()
    event.stopPropagation()
    
    const optionElement = event.currentTarget
    const period = optionElement.dataset.periodValue
    
    // Validate the period value
    const allowedPeriods = ['today', 'last_7_days', 'last_30_days', 'last_90_days']
    if (!allowedPeriods.includes(period)) {
      return
    }
    
    // Update button text
    const textElement = this.buttonTarget.querySelector('.period-selector-text')
    if (textElement) {
      textElement.textContent = optionElement.dataset.periodText
    }
    
    // Update visual selection state
    this.clearSelectedStates()
    this.markAsSelected(optionElement)
    
    this.close()
    
    // Navigate to the new URL with the selected period
    this.navigateToPeriod(period)
  }
  
  navigateToPeriod(period) {
    const basePath = this.basePathValue
    
    try {
      const url = new URL(basePath, window.location.origin)
      url.searchParams.set('period', period)
      window.location.href = url.toString()
    } catch (e) {
      // Fallback for older browsers without URL API
      const separator = basePath.indexOf('?') === -1 ? '?' : '&'
      window.location.href = basePath + separator + 'period=' + encodeURIComponent(period)
    }
  }
  
  clearSelectedStates() {
    this.optionTargets.forEach(option => {
      const checkIcon = option.querySelector('.period-check-icon')
      if (checkIcon) checkIcon.classList.add('hidden')
    })
  }
  
  markAsSelected(optionElement) {
    const checkIcon = optionElement.querySelector('.period-check-icon')
    if (checkIcon) checkIcon.classList.remove('hidden')
  }
  
  closeOnEscape(event) {
    if (event.key === 'Escape' && this.isOpen) {
      this.close()
    }
  }
  
  setupOutsideClickListener() {
    this.outsideClickHandler = (event) => {
      if (this.isOpen && !this.element.contains(event.target)) {
        this.close()
      }
    }

    // Store bound keydown handler so it can be properly removed
    this.keydownHandler = this.closeOnEscape.bind(this)

    document.addEventListener('click', this.outsideClickHandler)
    document.addEventListener('touchend', this.outsideClickHandler)
    document.addEventListener('keydown', this.keydownHandler)
  }
  
  removeOutsideClickListener() {
    if (this.outsideClickHandler) {
      document.removeEventListener('click', this.outsideClickHandler)
      document.removeEventListener('touchend', this.outsideClickHandler)
      document.removeEventListener('keydown', this.keydownHandler)
    }
  }
}
