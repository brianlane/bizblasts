import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "colorInput", "fontSelect", "previewFrame", "cssOutput", 
    "exportButton", "importInput", "resetButton"
  ]
  static values = { 
    themeId: String,
    previewUrl: String,
    updateUrl: String
  }

  connect() {
    this.initializeColorPickers()
    this.initializeLivePreview()
    this.debounceTimer = null
  }

  disconnect() {
    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer)
    }
  }

  initializeColorPickers() {
    this.colorInputTargets.forEach(input => {
      input.addEventListener('input', (event) => {
        this.updatePreview()
      })
    })
  }

  initializeLivePreview() {
    // Initialize with current theme
    this.updatePreview()
    
    // Set up observers for all form inputs
    this.element.addEventListener('input', (event) => {
      if (event.target.matches('input, select, textarea')) {
        this.debouncedUpdate()
      }
    })
  }

  debouncedUpdate() {
    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer)
    }
    
    this.debounceTimer = setTimeout(() => {
      this.updatePreview()
    }, 300)
  }

  updatePreview() {
    const themeData = this.gatherThemeData()
    const cssVariables = this.generateCSSVariables(themeData)
    
    // Update CSS output if target exists
    if (this.hasCssOutputTarget) {
      this.cssOutputTarget.textContent = cssVariables
    }
    
    // Update preview frame
    if (this.hasPreviewFrameTarget) {
      this.injectThemeCSS(cssVariables)
    }
  }

  gatherThemeData() {
    const formData = new FormData(this.element.querySelector('form'))
    const themeData = {
      color_scheme: {},
      typography: {},
      layout_config: {}
    }

    // Gather color scheme
    this.colorInputTargets.forEach(input => {
      const colorName = input.dataset.colorName
      if (colorName) {
        themeData.color_scheme[colorName] = input.value
      }
    })

    // Gather typography
    this.fontSelectTargets.forEach(select => {
      const fontProperty = select.dataset.fontProperty
      if (fontProperty) {
        themeData.typography[fontProperty] = select.value
      }
    })

    // Gather other form data
    for (let [key, value] of formData.entries()) {
      if (key.startsWith('website_theme[typography]')) {
        const prop = key.match(/\[([^\]]+)\]$/)?.[1]
        if (prop) themeData.typography[prop] = value
      } else if (key.startsWith('website_theme[layout_config]')) {
        const prop = key.match(/\[([^\]]+)\]$/)?.[1]
        if (prop) themeData.layout_config[prop] = value
      }
    }

    return themeData
  }

  generateCSSVariables(themeData) {
    let css = ':root {\n'
    
    // Color variables
    Object.entries(themeData.color_scheme).forEach(([key, value]) => {
      css += `  --color-${key.replace('_', '-')}: ${value};\n`
    })
    
    // Typography variables
    Object.entries(themeData.typography).forEach(([key, value]) => {
      css += `  --${key.replace('_', '-')}: ${value};\n`
    })
    
    // Layout variables
    Object.entries(themeData.layout_config).forEach(([key, value]) => {
      if (typeof value === 'string') {
        css += `  --layout-${key.replace('_', '-')}: ${value};\n`
      }
    })
    
    css += '}\n'
    return css
  }

  injectThemeCSS(cssVariables) {
    const previewDoc = this.previewFrameTarget.contentDocument
    if (!previewDoc) return

    // Remove existing theme styles
    const existingStyle = previewDoc.getElementById('theme-preview-styles')
    if (existingStyle) {
      existingStyle.remove()
    }

    // Add new theme styles
    const style = previewDoc.createElement('style')
    style.id = 'theme-preview-styles'
    style.textContent = cssVariables
    previewDoc.head.appendChild(style)
  }

  // Color Management
  updateColor(event) {
    const colorName = event.currentTarget.dataset.colorName
    const colorValue = event.currentTarget.value
    
    // Update any preview elements immediately
    this.updateColorPreview(colorName, colorValue)
    this.debouncedUpdate()
  }

  updateColorPreview(colorName, colorValue) {
    // Update color preview swatches if they exist
    const previewSwatch = this.element.querySelector(`[data-color-preview="${colorName}"]`)
    if (previewSwatch) {
      previewSwatch.style.backgroundColor = colorValue
    }
  }

  resetColors(event) {
    event.preventDefault()
    
    if (!confirm('Reset all colors to default? This cannot be undone.')) {
      return
    }

    // Reset to defaults (you could fetch these from the server)
    const defaultColors = {
      primary: '#1A5F7A',
      secondary: '#57C5B6',
      accent: '#FF8C42',
      dark: '#333333',
      light: '#F8F9FA',
      success: '#28A745',
      warning: '#FFC107',
      error: '#DC3545',
      info: '#17A2B8'
    }

    Object.entries(defaultColors).forEach(([name, value]) => {
      const input = this.element.querySelector(`[data-color-name="${name}"]`)
      if (input) {
        input.value = value
        this.updateColorPreview(name, value)
      }
    })

    this.updatePreview()
  }

  // Font Management
  updateFont(event) {
    this.debouncedUpdate()
  }

  previewFont(event) {
    const fontFamily = event.currentTarget.value
    const previewText = event.currentTarget.closest('.form-group').querySelector('.font-preview')
    
    if (previewText) {
      previewText.style.fontFamily = fontFamily
    }
  }

  // Theme Management
  saveTheme(event) {
    event.preventDefault()
    
    const formData = new FormData(event.currentTarget)
    
    fetch(this.updateUrlValue, {
      method: 'PATCH',
      body: formData,
      headers: {
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
        'Accept': 'application/json'
      }
    })
    .then(response => response.json())
    .then(data => {
      if (data.status === 'success') {
        this.showNotification('Theme saved successfully', 'success')
      } else {
        this.showNotification('Failed to save theme', 'error')
      }
    })
    .catch(error => {
      console.error('Error saving theme:', error)
      this.showNotification('Failed to save theme', 'error')
    })
  }

  activateTheme(event) {
    event.preventDefault()
    
    if (!confirm('Activate this theme? It will become the active theme for your website.')) {
      return
    }

    fetch(`/manage/website/themes/${this.themeIdValue}/activate`, {
      method: 'PATCH',
      headers: {
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
        'Accept': 'application/json'
      }
    })
    .then(response => response.json())
    .then(data => {
      if (data.status === 'success') {
        this.showNotification('Theme activated successfully', 'success')
        setTimeout(() => window.location.reload(), 1000)
      } else {
        this.showNotification('Failed to activate theme', 'error')
      }
    })
  }

  exportTheme(event) {
    event.preventDefault()
    
    fetch(`/manage/website/themes/${this.themeIdValue}/export`, {
      method: 'GET',
      headers: {
        'Accept': 'application/json'
      }
    })
    .then(response => response.json())
    .then(data => {
      this.downloadTheme(data)
    })
  }

  downloadTheme(themeData) {
    const dataStr = JSON.stringify(themeData, null, 2)
    const dataBlob = new Blob([dataStr], { type: 'application/json' })
    
    const link = document.createElement('a')
    link.href = URL.createObjectURL(dataBlob)
    link.download = `${themeData.name.replace(/\s+/g, '_').toLowerCase()}_theme.json`
    link.click()
    
    this.showNotification('Theme exported successfully', 'success')
  }

  importTheme(event) {
    const file = event.currentTarget.files[0]
    if (!file) return

    const reader = new FileReader()
    reader.onload = (e) => {
      try {
        const themeData = JSON.parse(e.target.result)
        this.applyImportedTheme(themeData)
        this.showNotification('Theme imported successfully', 'success')
      } catch (error) {
        this.showNotification('Invalid theme file', 'error')
      }
    }
    reader.readAsText(file)
  }

  applyImportedTheme(themeData) {
    // Apply colors
    if (themeData.color_scheme) {
      Object.entries(themeData.color_scheme).forEach(([name, value]) => {
        const input = this.element.querySelector(`[data-color-name="${name}"]`)
        if (input) {
          input.value = value
          this.updateColorPreview(name, value)
        }
      })
    }

    // Apply typography
    if (themeData.typography) {
      Object.entries(themeData.typography).forEach(([prop, value]) => {
        const input = this.element.querySelector(`[name*="[typography][${prop}]"]`)
        if (input) {
          input.value = value
        }
      })
    }

    // Apply layout config
    if (themeData.layout_config) {
      Object.entries(themeData.layout_config).forEach(([prop, value]) => {
        const input = this.element.querySelector(`[name*="[layout_config][${prop}]"]`)
        if (input) {
          input.value = value
        }
      })
    }

    // Update name if provided
    if (themeData.name) {
      const nameInput = this.element.querySelector('[name*="[name]"]')
      if (nameInput) {
        nameInput.value = `${themeData.name} (Imported)`
      }
    }

    this.updatePreview()
  }

  duplicateTheme(event) {
    event.preventDefault()
    
    fetch(`/manage/website/themes/${this.themeIdValue}/duplicate`, {
      method: 'POST',
      headers: {
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
      }
    })
    .then(response => {
      if (response.ok) {
        this.showNotification('Theme duplicated successfully', 'success')
        setTimeout(() => window.location.reload(), 1000)
      } else {
        this.showNotification('Failed to duplicate theme', 'error')
      }
    })
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
} 