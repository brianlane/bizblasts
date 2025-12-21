import { Controller } from "@hotwired/stimulus"

// Controls the dynamic form builder for job form templates
export default class extends Controller {
  static targets = ["fieldsContainer", "fieldItem", "fieldTemplate", "hiddenField", "emptyState", "dragHandle"]

  connect() {
    this.updateFieldNumbers()
    this.initializeDragAndDrop()
  }

  addField(event) {
    event.preventDefault()

    const template = this.fieldTemplateTarget.content.cloneNode(true)
    const fieldItem = template.querySelector('.field-item')

    this.fieldsContainerTarget.appendChild(template)
    this.updateFieldNumbers()
    this.toggleEmptyState()
    this.initializeDragAndDrop()

    // Focus on the label input of the new field
    const newField = this.fieldsContainerTarget.lastElementChild
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

  fieldTypeChanged(event) {
    const fieldItem = event.target.closest('.field-item')
    const optionsContainer = fieldItem.querySelector('.options-container')
    const selectedType = event.target.value

    if (selectedType === 'select') {
      optionsContainer.classList.remove('hidden')
    } else {
      optionsContainer.classList.add('hidden')
    }
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

    items.forEach(item => {
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
    })
  }

  beforeSubmit(event) {
    // Collect all field data and serialize to JSON
    const fields = []
    const fieldItems = this.fieldsContainerTarget.querySelectorAll('.field-item')

    fieldItems.forEach((item, index) => {
      const labelInput = item.querySelector('[data-field="label"]')
      const typeSelect = item.querySelector('[data-field="type"]')
      const helpTextInput = item.querySelector('[data-field="help_text"]')
      const optionsTextarea = item.querySelector('[data-field="options"]')
      const requiredCheckbox = item.querySelector('[data-field="required"]')

      // Preserve existing field ID if present, otherwise generate a new one
      const existingFieldId = item.dataset.fieldId
      const field = {
        id: existingFieldId || this.generateFieldId(),
        position: index,
        label: labelInput?.value || '',
        type: typeSelect?.value || 'text',
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
