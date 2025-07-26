import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["thumbnail", "statusIndicator", "actionsMenu"]
  static values = { 
    pageId: String,
    status: String,
    priority: Number,
    viewCount: Number,
    performanceScore: Number
  }

  connect() {
    this.initializeStatusIndicator()
    this.loadThumbnail()
    this.addHoverEffects()
  }

  initializeStatusIndicator() {
    if (this.hasStatusIndicatorTarget) {
      this.updateStatusIndicator()
    }
  }

  updateStatusIndicator() {
    const indicator = this.statusIndicatorTarget
    const status = this.statusValue
    
    // Remove existing classes
    indicator.classList.remove('bg-green-100', 'text-green-800', 'bg-yellow-100', 'text-yellow-800', 'bg-gray-100', 'text-gray-800')
    
    // Traffic light system
    switch(status) {
      case 'published':
        indicator.classList.add('bg-green-100', 'text-green-800')
        indicator.innerHTML = `
          <div class="flex items-center">
            <div class="w-2 h-2 bg-green-500 rounded-full mr-2"></div>
            Published
          </div>
        `
        break
      case 'draft':
        indicator.classList.add('bg-yellow-100', 'text-yellow-800')
        indicator.innerHTML = `
          <div class="flex items-center">
            <div class="w-2 h-2 bg-yellow-500 rounded-full mr-2"></div>
            Draft
          </div>
        `
        break
      default:
        indicator.classList.add('bg-gray-100', 'text-gray-800')
        indicator.innerHTML = `
          <div class="flex items-center">
            <div class="w-2 h-2 bg-gray-500 rounded-full mr-2"></div>
            Archived
          </div>
        `
    }

    // Add performance indicator if available
    if (this.performanceScoreValue > 0) {
      this.addPerformanceIndicator()
    }
  }

  addPerformanceIndicator() {
    const score = this.performanceScoreValue
    let color = 'red'
    let text = 'Poor'
    
    if (score >= 81) {
      color = 'green'
      text = 'Excellent'
    } else if (score >= 61) {
      color = 'blue'
      text = 'Good'
    } else if (score >= 31) {
      color = 'yellow'
      text = 'Fair'
    }

    const performanceEl = document.createElement('div')
    performanceEl.className = `text-xs mt-1 text-${color}-600`
    performanceEl.innerHTML = `⚡ ${text} (${score})`
    performanceEl.title = `Performance Score: ${score}/100`
    
    this.statusIndicatorTarget.appendChild(performanceEl)
  }

  addHoverEffects() {
    this.element.addEventListener('mouseenter', () => {
      this.element.style.transform = 'translateY(-2px)'
      this.element.style.boxShadow = '0 10px 25px rgba(0, 0, 0, 0.1)'
    })

    this.element.addEventListener('mouseleave', () => {
      this.element.style.transform = 'translateY(0)'
      this.element.style.boxShadow = '0 1px 3px rgba(0, 0, 0, 0.1)'
    })
  }

  async loadThumbnail() {
    if (!this.hasThumbnailTarget) return
    
    // Simulate loading thumbnail (in real app, this would fetch from server)
    setTimeout(() => {
      if (Math.random() > 0.5) {
        // Replace with actual thumbnail when available
        this.thumbnailTarget.style.backgroundImage = `linear-gradient(135deg, #667eea 0%, #764ba2 100%)`
        this.thumbnailTarget.innerHTML = `
          <div class="absolute inset-0 bg-black bg-opacity-20 flex items-center justify-center">
            <div class="text-white text-xs font-medium">Preview</div>
          </div>
        `
      }
    }, Math.random() * 1000)
  }

  toggleActionsMenu(event) {
    event.stopPropagation()
    
    if (this.hasActionsMenuTarget) {
      this.actionsMenuTarget.classList.toggle('hidden')
    }
  }

  closeActionsMenu() {
    if (this.hasActionsMenuTarget) {
      this.actionsMenuTarget.classList.add('hidden')
    }
  }

  // Quick actions
  async duplicatePage() {
    try {
      const response = await fetch(`/manage/website/pages/${this.pageIdValue}/duplicate`, {
        method: 'POST',
        headers: {
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
        }
      })

      if (response.ok) {
        window.location.reload()
      } else {
        throw new Error('Duplication failed')
      }
    } catch (error) {
      console.error('Duplication error:', error)
      alert('Failed to duplicate page')
    }
  }

  async publishPage() {
    try {
      const response = await fetch(`/manage/website/pages/${this.pageIdValue}/publish`, {
        method: 'PATCH',
        headers: {
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
        }
      })

      if (response.ok) {
        window.location.reload()
      } else {
        throw new Error('Publishing failed')
      }
    } catch (error) {
      console.error('Publishing error:', error)
      alert('Failed to publish page')
    }
  }

  // Analytics tracking
  trackView() {
    // Increment view count when page is visited via the admin interface
    fetch(`/manage/website/pages/${this.pageIdValue}/track_view`, {
      method: 'POST',
      headers: {
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
      }
    }).catch(error => {
      console.error('View tracking error:', error)
    })
  }

  // Priority indicators
  showPriorityIndicator() {
    const priority = this.priorityValue
    if (priority > 0) {
      const indicator = document.createElement('div')
      indicator.className = 'absolute top-2 left-2 px-2 py-1 rounded text-xs font-medium'
      
      if (priority >= 7) {
        indicator.className += ' bg-red-100 text-red-800'
        indicator.textContent = 'Critical'
      } else if (priority >= 4) {
        indicator.className += ' bg-orange-100 text-orange-800'
        indicator.textContent = 'High'
      } else {
        indicator.className += ' bg-blue-100 text-blue-800'
        indicator.textContent = 'Medium'
      }
      
      this.element.querySelector('.h-40').appendChild(indicator)
    }
  }
}