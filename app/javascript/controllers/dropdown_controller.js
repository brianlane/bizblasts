import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "menu", "option", "hidden"]
  static values = { 
    selectedValue: String,
    selectedText: String 
  }
  
  connect() {
    this.isOpen = false
    this.setInitialState()
    this.setupOutsideClickListener()
  }
  
  disconnect() {
    this.removeOutsideClickListener()
  }
  
  setInitialState() {
    // Set initial selected state if we have a selected value
    if (this.selectedValueValue) {
      const selectedOption = this.optionTargets.find(option => 
        option.dataset.itemId === this.selectedValueValue
      )
      if (selectedOption) {
        this.selectOption(selectedOption, false)
      }
    }
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
    
    // Handle mobile positioning
    if (window.innerWidth <= 640) {
      this.menuTarget.style.display = 'block'
      this.menuTarget.style.position = 'absolute'
      this.menuTarget.style.top = '100%'
      this.menuTarget.style.left = '0'
      this.menuTarget.style.right = '0'
      this.menuTarget.style.zIndex = '50'
      this.menuTarget.style.marginTop = '0.25rem'
    }
    
    // Handle viewport positioning
    this.handleViewportPositioning()
    
    this.isOpen = true
  }
  
  close() {
    this.menuTarget.classList.add('hidden')
    this.buttonTarget.setAttribute('aria-expanded', 'false')
    
    // Reset arrow rotation
    const arrow = this.buttonTarget.querySelector('svg')
    if (arrow) arrow.classList.remove('rotate-180')
    
    // Clear mobile styles
    if (window.innerWidth <= 640) {
      this.menuTarget.style.display = ''
      this.menuTarget.style.position = ''
      this.menuTarget.style.top = ''
      this.menuTarget.style.left = ''
      this.menuTarget.style.right = ''
      this.menuTarget.style.zIndex = ''
      this.menuTarget.style.marginTop = ''
    }
    
    this.isOpen = false
  }
  
  selectOption(optionElement, shouldClose = true) {
    const itemId = optionElement.dataset.itemId
    const itemText = optionElement.dataset.itemText
    
    // Update hidden field
    this.hiddenTarget.value = itemId
    
    // Update button text
    const textElement = this.buttonTarget.querySelector('.rich-dropdown-text') || 
                       this.buttonTarget.querySelector('.customer-dropdown-text') ||
                       this.buttonTarget.querySelector('span')
    
    if (textElement) {
      textElement.textContent = itemText
    }
    
    // Update visual selection state
    this.clearSelectedStates()
    this.markAsSelected(optionElement)
    
    // Store selected values
    this.selectedValueValue = itemId
    this.selectedTextValue = itemText
    
    if (shouldClose) {
      this.close()
    }
    
    // Trigger change event for form validation
    this.hiddenTarget.dispatchEvent(new Event('change', { bubbles: true }))
    
    // Trigger custom event for other listeners
    this.dispatch('selected', { 
      detail: { 
        value: itemId, 
        text: itemText,
        element: optionElement 
      } 
    })
  }
  
  clearSelectedStates() {
    this.optionTargets.forEach(option => {
      const checkIcon = option.querySelector('.absolute.inset-y-0.right-2')
      if (checkIcon) checkIcon.remove()
    })
  }
  
  markAsSelected(optionElement) {
    const checkIcon = document.createElement('span')
    checkIcon.className = 'absolute inset-y-0 right-2 flex items-center text-blue-600'
    checkIcon.innerHTML = `
      <svg class="h-5 w-5" fill="currentColor" viewBox="0 0 20 20">
        <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd"/>
      </svg>
    `
    optionElement.appendChild(checkIcon)
  }
  
  handleViewportPositioning() {
    const rect = this.buttonTarget.getBoundingClientRect()
    const viewportHeight = window.innerHeight
    const spaceBelow = viewportHeight - rect.bottom
    const dropdownHeight = this.menuTarget.scrollHeight
    
    if (spaceBelow < dropdownHeight && rect.top > dropdownHeight && window.innerWidth > 640) {
      this.menuTarget.style.bottom = '100%'
      this.menuTarget.style.top = 'auto'
      this.menuTarget.classList.add('mb-1')
      this.menuTarget.classList.remove('mt-1')
    } else if (window.innerWidth > 640) {
      this.menuTarget.style.top = '100%'
      this.menuTarget.style.bottom = 'auto'
      this.menuTarget.classList.add('mt-1')
      this.menuTarget.classList.remove('mb-1')
    }
  }
  
  // Action methods called from templates
  select(event) {
    event.preventDefault()
    event.stopPropagation()
    this.selectOption(event.currentTarget)
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
    
    document.addEventListener('click', this.outsideClickHandler)
    document.addEventListener('touchend', this.outsideClickHandler)
    document.addEventListener('keydown', this.closeOnEscape.bind(this))
  }
  
  removeOutsideClickListener() {
    if (this.outsideClickHandler) {
      document.removeEventListener('click', this.outsideClickHandler)
      document.removeEventListener('touchend', this.outsideClickHandler)
      document.removeEventListener('keydown', this.closeOnEscape.bind(this))
    }
  }
} 