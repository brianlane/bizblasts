import { Controller } from "@hotwired/stimulus"
import { createApp } from "vue"

export default class extends Controller {
  static targets = ["vueMount", "searchInput", "industryFilter", "templateGrid", "filterTabs", "emptyState", "previewModal", "previewFrame"]
  static values = { 
    businessId: String,
    businessIndustry: String,
    templatesUrl: String
  }

  connect() {
    this.mountVueApp()
    this.selectedTemplates = new Set()
    this.currentFilter = 'all'
    this.currentTemplateId = null
    this.setupMessageListener()
    console.log("Template browser connected")
  }

  disconnect() {
    if (this.vueApp) {
      this.vueApp.unmount()
    }
    if (this.messageHandler) {
      window.removeEventListener('message', this.messageHandler)
    }
  }

  mountVueApp() {
    if (!this.hasVueMountTarget) return

    this.vueApp = createApp({
      data() {
        return {
          templates: [],
          filteredTemplates: [],
          loading: true,
          searchQuery: '',
          industryFilter: 'all',
          selectedTemplate: null,
          previewMode: false,
          industries: [
            { value: 'all', label: 'All Industries' },
            { value: 'universal', label: 'Universal Templates' },
            // Add industry options dynamically
          ],
          sortBy: 'name',
          currentPage: 1,
          templatesPerPage: 12
        }
      },
      computed: {
        paginatedTemplates() {
          const start = (this.currentPage - 1) * this.templatesPerPage
          const end = start + this.templatesPerPage
          return this.filteredTemplates.slice(start, end)
        },
        totalPages() {
          return Math.ceil(this.filteredTemplates.length / this.templatesPerPage)
        }
      },
      methods: {
        async loadTemplates() {
          try {
            this.loading = true
            const response = await fetch(this.controller.templatesUrlValue)
            const data = await response.json()
            this.templates = data
            this.filteredTemplates = data
            this.populateIndustries()
          } catch (error) {
            console.error('Failed to load templates:', error)
          } finally {
            this.loading = false
          }
        },
        populateIndustries() {
          const industries = [...new Set(this.templates.map(t => t.industry))]
          this.industries = [
            { value: 'all', label: 'All Industries' },
            { value: 'universal', label: 'Universal Templates' },
            ...industries.filter(i => i !== 'universal').map(industry => ({
              value: industry,
              label: this.formatIndustryName(industry)
            }))
          ]
        },
        formatIndustryName(industry) {
          return industry.split('_').map(word => 
            word.charAt(0).toUpperCase() + word.slice(1)
          ).join(' ')
        },
        filterTemplates() {
          let filtered = this.templates

          // Search filter
          if (this.searchQuery) {
            const query = this.searchQuery.toLowerCase()
            filtered = filtered.filter(template => 
              template.name.toLowerCase().includes(query) ||
              template.description.toLowerCase().includes(query)
            )
          }

          // Industry filter
          if (this.industryFilter !== 'all') {
            if (this.industryFilter === 'universal') {
              filtered = filtered.filter(template => template.template_type === 'universal')
            } else {
              filtered = filtered.filter(template => template.industry === this.industryFilter)
            }
          }

          // Sort
          filtered.sort((a, b) => {
            switch (this.sortBy) {
              case 'name':
                return a.name.localeCompare(b.name)
              case 'industry':
                return a.industry.localeCompare(b.industry)
              case 'type':
                return a.template_type.localeCompare(b.template_type)
              default:
                return 0
            }
          })

          this.filteredTemplates = filtered
          this.currentPage = 1
        },
        selectTemplate(template) {
          this.selectedTemplate = template
          this.previewMode = false
        },
        previewTemplate(template) {
          this.selectedTemplate = template
          this.previewMode = true
          console.log('Vue: Previewing template:', template.id) // Debug log
          
          // Create a fake event object to pass to the Stimulus controller
          const fakeEvent = {
            currentTarget: { dataset: { templateId: template.id } },
            target: { dataset: { templateId: template.id } }
          }
          
          // Call the Stimulus controller method directly
          this.controller.previewTemplate(fakeEvent)
        },
        async applyTemplate(template) {
          if (!confirm(`Apply template "${template.name}"? This will replace your current pages.`)) {
            return
          }

          try {
            const response = await fetch(`/manage/website/templates/${template.id}/apply`, {
              method: 'POST',
              headers: {
                'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
                'Accept': 'application/json'
              }
            })

            const data = await response.json()
            
            if (data.status === 'success') {
              this.controller.showNotification('Template applied successfully!', 'success')
              setTimeout(() => {
                window.location.href = data.redirect_url
              }, 1500)
            } else {
              this.controller.showNotification(data.message || 'Failed to apply template', 'error')
            }
          } catch (error) {
            console.error('Error applying template:', error)
            this.controller.showNotification('Failed to apply template', 'error')
          }
        },
        canUseTemplate(template) {
          return template.can_use
        },
        getTemplateBadgeClass(template) {
          if (template.template_type === 'universal') return 'badge-universal'
          return 'badge-industry'
        },
        getTemplateBadgeText(template) {
          if (template.template_type === 'universal') return 'Universal'
          return 'Industry'
        }
      },
      watch: {
        searchQuery() { this.filterTemplates() },
        industryFilter() { this.filterTemplates() },
        sortBy() { this.filterTemplates() }
      },
      mounted() {
        this.loadTemplates()
      },
      template: `
        <div class="template-browser">
          <!-- Search and Filters -->
          <div class="template-filters mb-6">
            <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
              <div>
                <label class="block text-sm font-medium text-gray-700 mb-2">Search Templates</label>
                <input 
                  v-model="searchQuery"
                  type="text" 
                  placeholder="Search by name or description..."
                  class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                >
              </div>
              <div>
                <label class="block text-sm font-medium text-gray-700 mb-2">Industry</label>
                <select 
                  v-model="industryFilter"
                  class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                >
                  <option v-for="industry in industries" :key="industry.value" :value="industry.value">
                    {{ industry.label }}
                  </option>
                </select>
              </div>
              <div>
                <label class="block text-sm font-medium text-gray-700 mb-2">Sort By</label>
                <select 
                  v-model="sortBy"
                  class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                >
                  <option value="name">Name</option>
                  <option value="industry">Industry</option>
                  <option value="type">Type</option>
                </select>
              </div>
            </div>
          </div>

          <!-- Loading State -->
          <div v-if="loading" class="text-center py-8">
            <div class="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-500 mx-auto"></div>
            <p class="mt-4 text-gray-600">Loading templates...</p>
          </div>

          <!-- Template Grid -->
          <div v-else class="template-grid">
            <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-6">
              <div 
                v-for="template in paginatedTemplates" 
                :key="template.id"
                class="template-card bg-white rounded-lg shadow-md overflow-hidden hover:shadow-lg transition-shadow duration-200"
                :class="{ 'ring-2 ring-blue-500': selectedTemplate?.id === template.id }"
              >
                <!-- Template Preview Image -->
                <div class="aspect-w-16 aspect-h-9 bg-gray-200">
                  <img 
                    :src="template.preview_image_url" 
                    :alt="template.name"
                    class="w-full h-48 object-cover"
                    @error="$event.target.src = '/assets/template-default.jpg'"
                  >
                  <div class="absolute top-2 right-2">
                    <span 
                      class="badge px-2 py-1 rounded text-xs font-medium"
                      :class="getTemplateBadgeClass(template)"
                    >
                      {{ getTemplateBadgeText(template) }}
                    </span>
                  </div>
                </div>

                <!-- Template Info -->
                <div class="p-4">
                  <h3 class="font-semibold text-lg text-gray-900 mb-2">{{ template.name }}</h3>
                  <p class="text-gray-600 text-sm mb-3 line-clamp-2">{{ template.description }}</p>
                  
                  <div class="flex items-center justify-between">
                    <span class="text-xs text-gray-500">
                      {{ formatIndustryName(template.industry) }}
                    </span>
                    <div class="flex space-x-2">
                      <button 
                        @click="previewTemplate(template)"
                        class="px-3 py-1 text-xs bg-gray-100 text-gray-700 rounded hover:bg-gray-200 transition-colors"
                      >
                        Preview
                      </button>
                      <button 
                        @click="applyTemplate(template)"
                        :disabled="!canUseTemplate(template)"
                        class="px-3 py-1 text-xs bg-blue-500 text-white rounded hover:bg-blue-600 transition-colors disabled:bg-gray-300 disabled:cursor-not-allowed"
                      >
                        {{ canUseTemplate(template) ? 'Apply' : 'Upgrade Required' }}
                      </button>
                    </div>
                  </div>
                </div>
              </div>
            </div>

            <!-- Pagination -->
            <div v-if="totalPages > 1" class="mt-8 flex justify-center">
              <nav class="flex space-x-2">
                <button 
                  @click="currentPage = Math.max(1, currentPage - 1)"
                  :disabled="currentPage === 1"
                  class="px-3 py-2 text-sm bg-white border border-gray-300 rounded-md hover:bg-gray-50 disabled:bg-gray-100 disabled:cursor-not-allowed"
                >
                  Previous
                </button>
                
                <template v-for="page in Math.min(totalPages, 5)" :key="page">
                  <button 
                    @click="currentPage = page"
                    :class="page === currentPage ? 'bg-blue-500 text-white' : 'bg-white text-gray-700 hover:bg-gray-50'"
                    class="px-3 py-2 text-sm border border-gray-300 rounded-md"
                  >
                    {{ page }}
                  </button>
                </template>
                
                <button 
                  @click="currentPage = Math.min(totalPages, currentPage + 1)"
                  :disabled="currentPage === totalPages"
                  class="px-3 py-2 text-sm bg-white border border-gray-300 rounded-md hover:bg-gray-50 disabled:bg-gray-100 disabled:cursor-not-allowed"
                >
                  Next
                </button>
              </nav>
            </div>

            <!-- No Results -->
            <div v-if="filteredTemplates.length === 0" class="text-center py-8">
              <p class="text-gray-600">No templates found matching your criteria.</p>
            </div>
          </div>
        </div>
      `
    })

    // Make controller available to Vue app
    this.vueApp.config.globalProperties.controller = this
    this.vueApp.mount(this.vueMountTarget)
  }

  showTemplatePreview(template) {
    // Create and show preview modal
    const modal = this.createPreviewModal(template)
    document.body.appendChild(modal)
  }

  createPreviewModal(template) {
    const modal = document.createElement('div')
    modal.className = 'fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50'
    modal.innerHTML = `
      <div class="bg-white rounded-lg max-w-4xl max-h-[90vh] w-full mx-4 overflow-hidden">
        <div class="flex items-center justify-between p-4 border-b">
          <h3 class="text-lg font-semibold">${template.name} - Preview</h3>
          <button class="text-gray-400 hover:text-gray-600" onclick="this.closest('.fixed').remove()">
            <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
            </svg>
          </button>
        </div>
        <div class="p-4">
          <iframe 
            src="/manage/website/templates/${template.id}/preview" 
            class="w-full h-96 border border-gray-300 rounded"
            loading="lazy">
          </iframe>
        </div>
        <div class="flex justify-end space-x-3 p-4 border-t">
          <button 
            onclick="this.closest('.fixed').remove()"
            class="px-4 py-2 text-gray-700 bg-gray-100 rounded hover:bg-gray-200"
          >
            Close
          </button>
          <button 
            onclick="this.closest('.fixed').remove(); window.templateBrowserController.applyTemplate('${template.id}')"
            class="px-4 py-2 bg-blue-500 text-white rounded hover:bg-blue-600"
          >
            Apply Template
          </button>
        </div>
      </div>
    `
    return modal
  }

  async applyTemplate(templateId) {
    try {
      const response = await fetch(`/manage/website/templates/${templateId}/apply`, {
        method: 'POST',
        headers: {
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
          'Accept': 'application/json'
        }
      })

      const data = await response.json()
      
      if (data.status === 'success') {
        this.showNotification('Template applied successfully!', 'success')
        setTimeout(() => {
          window.location.href = data.redirect_url
        }, 1500)
      } else {
        this.showNotification(data.message || 'Failed to apply template', 'error')
      }
    } catch (error) {
      console.error('Error applying template:', error)
      this.showNotification('Failed to apply template', 'error')
    }
  }

  showNotification(message, type = 'info') {
    const notification = document.createElement('div')
    notification.className = `notification notification-${type}`
    notification.textContent = message
    notification.style.cssText = `
      position: fixed;
      top: 20px;
      right: 20px;
      background: ${type === 'success' ? '#10b981' : type === 'error' ? '#ef4444' : '#3b82f6'};
      color: white;
      padding: 12px 24px;
      border-radius: 6px;
      z-index: 1000;
      box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
    `
    
    document.body.appendChild(notification)
    
    setTimeout(() => {
      notification.remove()
    }, 3000)
  }

  filterTemplates(event) {
    const filter = event.target.dataset.filter
    this.currentFilter = filter
    
    // Update active tab
    this.filterTabsTargets.forEach(tab => {
      const tabFilter = tab.dataset.filter
      if (tabFilter === filter) {
        tab.classList.add('active')
      } else {
        tab.classList.remove('active')
      }
    })
    
    // Filter template cards
    const templateCards = this.templateGridTarget.querySelectorAll('.template-card')
    let visibleCount = 0
    
    templateCards.forEach(card => {
      const shouldShow = this.shouldShowTemplate(card, filter)
      
      if (shouldShow) {
        card.classList.remove('hidden')
        visibleCount++
      } else {
        card.classList.add('hidden')
      }
    })
    
    // Show/hide empty state
    if (visibleCount === 0) {
      this.emptyStateTarget.classList.remove('hidden')
      this.templateGridTarget.classList.add('hidden')
    } else {
      this.emptyStateTarget.classList.add('hidden')
      this.templateGridTarget.classList.remove('hidden')
    }
  }

  shouldShowTemplate(card, filter) {
    const industry = card.dataset.templateIndustry
    const type = card.dataset.templateType
    const isPremium = card.dataset.templatePremium === 'true'
    
    switch (filter) {
      case 'all':
        return true
      case 'universal':
        return industry === 'universal' || type === 'universal_template'
      case 'industry': {
        // Get business industry from the page context
        const businessIndustry = this.getBusinessIndustry()
        return industry === businessIndustry
      }
      case 'premium':
        return isPremium
      default:
        return true
    }
  }

  getBusinessIndustry() {
    // Get business industry from meta tag or global variable
    const industryMeta = document.querySelector('meta[name="business-industry"]')
    return industryMeta ? industryMeta.content : null
  }

  async previewTemplate(event) {
    // Get template ID from the button or closest element with data-template-id
    let templateId = event.currentTarget.dataset.templateId
    if (!templateId) {
      templateId = event.target.dataset.templateId
    }
    if (!templateId) {
      const buttonElement = event.target.closest('[data-template-id]')
      templateId = buttonElement?.dataset.templateId
    }
    
    if (!templateId) {
      console.error('No template ID found')
      this.showNotification('Template ID not found', 'error')
      return
    }
    
    console.log('Previewing template:', templateId) // Debug log
    this.currentTemplateId = templateId
    
    try {
      // Clear previous iframe content
      this.previewFrameTarget.src = 'about:blank'
      
      // Show modal immediately
      this.previewModalTarget.classList.remove('hidden')
      
      // Hide navigation elements and prevent body scroll
      document.body.classList.add('modal-open')
      this.hideNavigationElements()
      
      // Load template preview with a slight delay to ensure iframe clears
      setTimeout(() => {
        const previewUrl = `/manage/website/templates/${templateId}/preview`
        console.log('Loading preview URL:', previewUrl) // Debug log
        this.previewFrameTarget.src = previewUrl
      }, 100)
      
    } catch (error) {
      console.error('Error previewing template:', error)
      this.showNotification('Failed to load template preview', 'error')
      this.closePreview()
    }
  }

  closePreview() {
    console.log('Closing preview') // Debug log
    this.previewModalTarget.classList.add('hidden')
    this.previewFrameTarget.src = 'about:blank'
    this.currentTemplateId = null
    
    // Restore navigation elements and body scroll
    document.body.classList.remove('modal-open')
    this.showNavigationElements()
  }

  async applyCurrentTemplate() {
    if (this.currentTemplateId) {
      await this.doApplyTemplate(this.currentTemplateId)
    }
  }

  async doApplyTemplate(templateId) {
    if (!confirm('Apply this template? This will update your website theme and may create new pages. Your existing content will be preserved.')) {
      return
    }

    try {
      // Show loading state
      this.showNotification('Applying template...', 'info')
      
      const response = await fetch(`/manage/website/templates/${templateId}/apply`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
        }
      })

      if (response.ok) {
        const result = await response.json()
        this.showNotification('Template applied successfully! Redirecting...', 'success')
        
        // Close preview if open
        this.closePreview()
        
        // Redirect to pages or themes after a delay
        setTimeout(() => {
          window.location.href = '/manage/website/pages'
        }, 2000)
        
      } else {
        const error = await response.json()
        throw new Error(error.message || 'Failed to apply template')
      }
      
    } catch (error) {
      console.error('Error applying template:', error)
      this.showNotification(`Failed to apply template: ${error.message}`, 'error')
    }
  }

  // Search functionality
  searchTemplates(event) {
    const searchTerm = event.target.value.toLowerCase()
    const templateCards = this.templateGridTarget.querySelectorAll('.template-card')
    let visibleCount = 0
    
    templateCards.forEach(card => {
      const templateName = card.querySelector('h3').textContent.toLowerCase()
      const templateDescription = card.querySelector('p').textContent.toLowerCase()
      
      const matchesSearch = templateName.includes(searchTerm) || 
                           templateDescription.includes(searchTerm)
      const matchesFilter = this.shouldShowTemplate(card, this.currentFilter)
      
      if (matchesSearch && matchesFilter) {
        card.classList.remove('hidden')
        visibleCount++
      } else {
        card.classList.add('hidden')
      }
    })
    
    // Show/hide empty state
    if (visibleCount === 0) {
      this.emptyStateTarget.classList.remove('hidden')
      this.templateGridTarget.classList.add('hidden')
    } else {
      this.emptyStateTarget.classList.add('hidden')
      this.templateGridTarget.classList.remove('hidden')
    }
  }

  // Keyboard navigation
  handleKeydown(event) {
    if (event.key === 'Escape') {
      this.closePreview()
    }
  }

  // Prevent modal from closing when clicking inside
  stopPropagation(event) {
    event.stopPropagation()
  }

  // Setup message listener for iframe communication
  setupMessageListener() {
    this.messageHandler = (event) => {
      if (event.data && event.data.action) {
        switch (event.data.action) {
          case 'applyTemplate':
            if (event.data.templateId) {
              this.doApplyTemplate(event.data.templateId)
            }
            break
          case 'closePreview':
            this.closePreview()
            break
        }
      }
    }
    window.addEventListener('message', this.messageHandler)
  }

  hideNavigationElements() {
    // Hide the main navigation tabs (Pages, Templates, Themes)
    const mainNavigation = document.querySelectorAll('nav')
    mainNavigation.forEach(nav => {
      nav.style.display = 'none'
      nav.setAttribute('data-hidden-by-modal', 'true')
    })
    
    // Hide the filter tabs (All Templates, Universal, My Industry)
    const filterTabs = document.querySelectorAll('.bg-white.border.border-gray-200.rounded-lg.p-1')
    filterTabs.forEach(tabs => {
      tabs.style.display = 'none'
      tabs.setAttribute('data-hidden-by-modal', 'true')
    })
  }

  showNavigationElements() {
    // Show the main navigation tabs
    const hiddenNavigation = document.querySelectorAll('[data-hidden-by-modal="true"]')
    hiddenNavigation.forEach(element => {
      element.style.display = ''
      element.removeAttribute('data-hidden-by-modal')
    })
  }

  // Template favoriting (future feature)
  toggleFavorite(event) {
    const templateId = event.target.dataset.templateId
    // Implementation for favoriting templates
    console.log('Toggle favorite for template:', templateId)
  }

  // Category quick filters
  filterByCategory(event) {
    const category = event.target.dataset.category
    
    const templateCards = this.templateGridTarget.querySelectorAll('.template-card')
    let visibleCount = 0
    
    templateCards.forEach(card => {
      const templateIndustry = card.dataset.templateIndustry
      
      if (category === 'all' || templateIndustry === category) {
        card.classList.remove('hidden')
        visibleCount++
      } else {
        card.classList.add('hidden')
      }
    })
    
    // Update visibility
    if (visibleCount === 0) {
      this.emptyStateTarget.classList.remove('hidden')
      this.templateGridTarget.classList.add('hidden')
    } else {
      this.emptyStateTarget.classList.add('hidden')
      this.templateGridTarget.classList.remove('hidden')
    }
  }
} 