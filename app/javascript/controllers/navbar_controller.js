import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["sidebar", "overlay", "toggle", "desktopToggle", "desktopToggleIcon", "mainContent"]
  
  connect() {
    this.sidebarOpen = window.innerWidth >= 1024 // Default open on desktop
    this.setInitialState()
    this.setupEventListeners()
  }

  disconnect() {
    // Clean up event listeners
    window.removeEventListener('resize', this.handleResize)
  }

  setupEventListeners() {
    this.handleResize = this.handleResize.bind(this)
    window.addEventListener('resize', this.handleResize)

    // Close sidebar when clicking on navigation links on mobile
    const navLinks = this.sidebarTarget.querySelectorAll('a')
    navLinks.forEach(link => {
      link.addEventListener('click', () => {
        if (window.innerWidth < 1024) {
          this.closeSidebar()
        }
      })
    })
  }

  setInitialState() {
    const isLargeScreen = window.innerWidth >= 1024
    
    if (isLargeScreen) {
      // Desktop: start with sidebar open
      this.sidebarOpen = true
      this.sidebarTarget.classList.remove('-translate-x-full')
      this.sidebarTarget.classList.add('translate-x-0')
      
      if (this.hasDesktopToggleTarget) {
        this.desktopToggleTarget.style.left = '270px'
        this.desktopToggleTarget.classList.add('sidebar-open')
      }
      
      if (this.hasDesktopToggleIconTarget) {
        this.desktopToggleIconTarget.innerHTML = '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>'
      }
      
      // Hide mobile toggle on desktop
      if (this.hasToggleTarget) {
        this.toggleTarget.style.display = 'none'
      }
    } else {
      // Mobile: start with sidebar closed
      this.sidebarOpen = false
      this.sidebarTarget.classList.add('-translate-x-full')
      this.sidebarTarget.classList.remove('translate-x-0')
      this.sidebarTarget.classList.remove('show')
      
      if (this.hasToggleTarget) {
        this.toggleTarget.style.display = 'block'
      }
      
      if (this.hasDesktopToggleTarget) {
        this.desktopToggleTarget.style.left = '16px'
        this.desktopToggleTarget.classList.remove('sidebar-open')
      }
      
      if (this.hasDesktopToggleIconTarget) {
        this.desktopToggleIconTarget.innerHTML = '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 12h16M4 18h16"></path>'
      }
    }
    
    if (this.hasOverlayTarget) {
      this.overlayTarget.classList.add('hidden')
      this.overlayTarget.classList.remove('show')
    }
    
    document.body.style.overflow = ''
  }

  updateSidebarState() {
    const isLargeScreen = window.innerWidth >= 1024
    
    if (isLargeScreen) {
      // Desktop behavior
      if (this.sidebarOpen) {
        this.sidebarTarget.classList.remove('-translate-x-full')
        this.sidebarTarget.classList.add('translate-x-0')
        
        if (this.hasDesktopToggleTarget) {
          this.desktopToggleTarget.style.left = '270px'
          this.desktopToggleTarget.classList.add('sidebar-open')
        }
        
        if (this.hasDesktopToggleIconTarget) {
          this.desktopToggleIconTarget.innerHTML = '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>'
        }
        
        if (this.hasToggleTarget) {
          this.toggleTarget.style.display = 'none'
        }
      } else {
        this.sidebarTarget.classList.add('-translate-x-full')
        this.sidebarTarget.classList.remove('translate-x-0')
        
        if (this.hasDesktopToggleTarget) {
          this.desktopToggleTarget.style.left = '16px'
          this.desktopToggleTarget.classList.remove('sidebar-open')
        }
        
        if (this.hasDesktopToggleIconTarget) {
          this.desktopToggleIconTarget.innerHTML = '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 12h16M4 18h16"></path>'
        }
        
        if (this.hasToggleTarget) {
          this.toggleTarget.style.display = 'none'
        }
      }
      
      if (this.hasOverlayTarget) {
        this.overlayTarget.classList.add('hidden')
      }
      
      document.body.style.overflow = ''
    } else {
      // Mobile behavior
      if (this.hasDesktopToggleTarget) {
        this.desktopToggleTarget.style.left = '16px'
        this.desktopToggleTarget.classList.remove('sidebar-open')
      }
      
      if (this.sidebarOpen) {
        this.sidebarTarget.classList.remove('-translate-x-full')
        this.sidebarTarget.classList.add('translate-x-0')
        this.sidebarTarget.classList.add('show')
        
        if (this.hasToggleTarget) {
          this.toggleTarget.style.display = 'none'
        }
        
        if (this.hasOverlayTarget) {
          this.overlayTarget.classList.remove('hidden')
          this.overlayTarget.classList.add('show')
        }
        
        document.body.style.overflow = 'hidden'
      } else {
        this.sidebarTarget.classList.add('-translate-x-full')
        this.sidebarTarget.classList.remove('translate-x-0')
        this.sidebarTarget.classList.remove('show')
        
        if (this.hasToggleTarget) {
          this.toggleTarget.style.display = 'block'
        }
        
        if (this.hasOverlayTarget) {
          this.overlayTarget.classList.add('hidden')
          this.overlayTarget.classList.remove('show')
        }
        
        document.body.style.overflow = ''
      }
    }
  }

  toggleSidebar() {
    this.sidebarOpen = !this.sidebarOpen
    this.updateSidebarState()
  }

  closeSidebar() {
    this.sidebarOpen = false
    this.updateSidebarState()
  }

  // Action methods for Stimulus
  toggle(event) {
    event.preventDefault()
    this.toggleSidebar()
  }

  close(event) {
    event.preventDefault()
    this.closeSidebar()
  }

  overlayClick(event) {
    event.preventDefault()
    this.closeSidebar()
  }

  handleResize() {
    // Reinitialize state on screen size change
    this.setInitialState()
  }
} 