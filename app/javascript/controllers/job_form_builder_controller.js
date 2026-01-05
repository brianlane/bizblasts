import { Controller } from "@hotwired/stimulus"

// Controls the dynamic form builder for job form templates
export default class extends Controller {
  static targets = ["fieldsContainer", "fieldItem", "fieldTemplate", "hiddenField", "emptyState", "dragHandle"]

  connect() {
    this.updateFieldNumbers()
    this.initializeDragAndDrop()
    this.setupOutsideClickListener()
  }

  disconnect() {
    this.removeOutsideClickListener()
  }

  addField(event) {
    event.preventDefault()

    const template = this.fieldTemplateTarget.content.cloneNode(true)
    const fieldItem = template.querySelector('.field-item')

    this.fieldsContainerTarget.appendChild(template)
    this.updateFieldNumbers()
    this.toggleEmptyState()

    // Only initialize drag-and-drop for the newly added field
    const newField = this.fieldsContainerTarget.lastElementChild
    this.initializeDragAndDropForItem(newField)
    this.initializeFieldTypeDropdown(newField)

    // Focus on the label input of the new field
    const labelInput = newField.querySelector('[data-field="label"]')
    if (labelInput) {
      labelInput.focus()
    }
  }

  removeField(event) {
    event.preventDefault()

    const fieldItem = event.target.closest('.field-item')
    if (fieldItem) {
      fieldItem.remove()
      this.updateFieldNumbers()
      this.toggleEmptyState()
    }
  }

  // Handle field type change from the dropdown controller
  fieldTypeChanged(event) {
    const fieldItem = event.target.closest('.field-item')
    if (!fieldItem) return
    
    const optionsContainer = fieldItem.querySelector('.options-container')
    const hiddenInput = fieldItem.querySelector('[data-field="type"]')
    const selectedType = hiddenInput?.value || event.detail?.value
    
    if (optionsContainer) {
      if (selectedType === 'select') {
        optionsContainer.classList.remove('hidden')
      } else {
        optionsContainer.classList.add('hidden')
      }
    }
  }

  // Toggle field type dropdown (for template-based fields)
  toggleFieldTypeDropdown(event) {
    event.preventDefault()
    event.stopPropagation()

    const button = event.currentTarget
    const dropdown = button.closest('.field-type-dropdown')
    const menu = dropdown.querySelector('.field-type-menu')

    // Close all other dropdowns first
    this.closeAllFieldTypeDropdowns()

    // Toggle this menu
    if (menu.classList.contains('hidden')) {
      menu.classList.remove('hidden')
      const arrow = button.querySelector('svg')
      if (arrow) arrow.classList.add('rotate-180')
    } else {
      menu.classList.add('hidden')
      const arrow = button.querySelector('svg')
      if (arrow) arrow.classList.remove('rotate-180')
    }
  }

  // Select field type from dropdown (for template-based fields)
  selectFieldType(event) {
    event.preventDefault()
    event.stopPropagation()

    const option = event.currentTarget
    const typeValue = option.dataset.typeValue
    const dropdown = option.closest('.field-type-dropdown')
    const fieldItem = option.closest('.field-item')

    // Update hidden input
    const hiddenInput = dropdown.querySelector('[data-field="type"]')
    if (hiddenInput) {
      hiddenInput.value = typeValue
    }

    // Update button text
    const textEl = dropdown.querySelector('.field-type-text')
    if (textEl) {
      textEl.textContent = this.humanize(typeValue)
    }

    // Close menu
    const menu = dropdown.querySelector('.field-type-menu')
    if (menu) {
      menu.classList.add('hidden')
    }

    // Reset arrow rotation
    const arrow = dropdown.querySelector('button svg')
    if (arrow) arrow.classList.remove('rotate-180')

    // Toggle options container
    const optionsContainer = fieldItem.querySelector('.options-container')
    if (optionsContainer) {
      if (typeValue === 'select') {
        optionsContainer.classList.remove('hidden')
      } else {
        optionsContainer.classList.add('hidden')
      }
    }
  }

  closeAllFieldTypeDropdowns() {
    const allDropdowns = this.element.querySelectorAll('.field-type-dropdown')
    allDropdowns.forEach(dropdown => {
      const menu = dropdown.querySelector('.field-type-menu')
      const arrow = dropdown.querySelector('button svg')
      if (menu) menu.classList.add('hidden')
      if (arrow) arrow.classList.remove('rotate-180')
    })
  }

  initializeFieldTypeDropdown(fieldItem) {
    // The dropdown is already set up with data-action attributes
    // Just need to make sure it works with the Stimulus actions
  }

  humanize(str) {
    return str.replace(/_/g, ' ').replace(/\b\w/g, l => l.toUpperCase())
  }

  updateFieldNumbers() {
    const fieldItems = this.fieldsContainerTarget.querySelectorAll('.field-item')
    fieldItems.forEach((item, index) => {
      const fieldNumber = item.querySelector('.field-number')
      if (fieldNumber) {
        fieldNumber.textContent = `Field ${index + 1}`
      }
      item.dataset.position = index
    })
  }

  toggleEmptyState() {
    const fieldItems = this.fieldsContainerTarget.querySelectorAll('.field-item')
    if (this.hasEmptyStateTarget) {
      if (fieldItems.length === 0) {
        this.emptyStateTarget.classList.remove('hidden')
      } else {
        this.emptyStateTarget.classList.add('hidden')
      }
    }
  }

  initializeDragAndDrop() {
    const container = this.fieldsContainerTarget
    const items = container.querySelectorAll('.field-item')
    items.forEach(item => this.initializeDragAndDropForItem(item))
  }

  initializeDragAndDropForItem(item) {
    // Skip if already initialized (check for a marker attribute)
    if (item.dataset.dragInitialized === 'true') {
      return
    }
    item.dataset.dragInitialized = 'true'

    const container = this.fieldsContainerTarget
    const handle = item.querySelector('[data-job-form-builder-target="dragHandle"]')

    if (handle) {
      handle.setAttribute('draggable', true)

      handle.addEventListener('dragstart', (e) => {
        item.classList.add('opacity-50')
        e.dataTransfer.effectAllowed = 'move'
        e.dataTransfer.setData('text/plain', item.dataset.position)
      })

      handle.addEventListener('dragend', () => {
        item.classList.remove('opacity-50')
      })
    }

    item.addEventListener('dragover', (e) => {
      e.preventDefault()
      e.dataTransfer.dropEffect = 'move'
      item.classList.add('border-blue-500')
    })

    item.addEventListener('dragleave', () => {
      item.classList.remove('border-blue-500')
    })

    item.addEventListener('drop', (e) => {
      e.preventDefault()
      item.classList.remove('border-blue-500')

      const fromIndex = parseInt(e.dataTransfer.getData('text/plain'))
      const toIndex = parseInt(item.dataset.position)

      if (fromIndex !== toIndex) {
        const items = Array.from(container.querySelectorAll('.field-item'))
        const fromItem = items[fromIndex]
        const toItem = items[toIndex]

        if (fromIndex < toIndex) {
          toItem.after(fromItem)
        } else {
          toItem.before(fromItem)
        }

        this.updateFieldNumbers()
      }
    })
  }

  setupOutsideClickListener() {
    this.outsideClickHandler = (event) => {
      // Close field type dropdowns when clicking outside
      if (!event.target.closest('.field-type-dropdown')) {
        this.closeAllFieldTypeDropdowns()
      }
    }
    document.addEventListener('click', this.outsideClickHandler)
  }

  removeOutsideClickListener() {
    if (this.outsideClickHandler) {
      document.removeEventListener('click', this.outsideClickHandler)
    }
  }

  beforeSubmit(event) {
    // Collect all field data and serialize to JSON
    const fields = []
    const fieldItems = this.fieldsContainerTarget.querySelectorAll('.field-item')

    fieldItems.forEach((item, index) => {
      const labelInput = item.querySelector('[data-field="label"]')
      const typeInput = item.querySelector('[data-field="type"]')
      const helpTextInput = item.querySelector('[data-field="help_text"]')
      const optionsTextarea = item.querySelector('[data-field="options"]')
      const requiredCheckbox = item.querySelector('[data-field="required"]')

      // Preserve existing field ID if present, otherwise generate a new one
      const existingFieldId = item.dataset.fieldId
      const field = {
        id: existingFieldId || this.generateFieldId(),
        position: index,
        label: labelInput?.value || '',
        type: typeInput?.value || 'text',
        help_text: helpTextInput?.value || '',
        required: requiredCheckbox?.checked || false
      }

      // Add options for select fields
      if (field.type === 'select' && optionsTextarea?.value) {
        field.options = optionsTextarea.value.split('\n').map(opt => opt.trim()).filter(opt => opt !== '')
      }

      // Only add fields that have a label
      if (field.label.trim() !== '') {
        fields.push(field)
      }
    })

    // Store in hidden field
    if (this.hasHiddenFieldTarget) {
      this.hiddenFieldTarget.value = JSON.stringify(fields)
    }
  }

  generateFieldId() {
    return 'field_' + Math.random().toString(36).substr(2, 9)
  }
}
