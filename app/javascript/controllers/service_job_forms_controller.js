import { Controller } from "@hotwired/stimulus"

// Controls the job form assignment UI for new services
export default class extends Controller {
  static targets = ["container", "templateSelect", "timingSelect"]

  connect() {
    this.formIndex = 0
  }

  addForm(event) {
    event.preventDefault()

    const templateSelect = this.templateSelectTarget
    const timingSelect = this.timingSelectTarget

    // Get selected template
    const selectedOption = templateSelect.options[templateSelect.selectedIndex]
    if (!selectedOption || !selectedOption.value) {
      alert('Please select a form template')
      return
    }

    const templateId = selectedOption.value
    const templateName = selectedOption.dataset.name
    const templateType = selectedOption.dataset.type
    const timing = timingSelect.value

    // Check if this template is already added
    const existingForms = this.containerTarget.querySelectorAll('[data-template-id]')
    for (const form of existingForms) {
      if (form.dataset.templateId === templateId) {
        alert('This form is already assigned')
        return
      }
    }

    // Create the form item
    const formItem = this.createFormItem(templateId, templateName, templateType, timing)
    this.containerTarget.appendChild(formItem)

    // Reset selects
    templateSelect.selectedIndex = 0

    this.formIndex++
  }

  removeForm(event) {
    event.preventDefault()
    const formItem = event.target.closest('[data-template-id]')
    if (formItem) {
      formItem.remove()
    }
  }

  createFormItem(templateId, templateName, templateType, timing) {
    const div = document.createElement('div')
    div.className = 'flex items-center justify-between p-3 bg-white dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700'
    div.dataset.templateId = templateId

    // Create content container
    const contentDiv = document.createElement('div')
    contentDiv.className = 'flex items-center'

    // Create SVG icon
    const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg')
    svg.setAttribute('class', 'w-5 h-5 text-blue-500 mr-3')
    svg.setAttribute('fill', 'none')
    svg.setAttribute('stroke', 'currentColor')
    svg.setAttribute('viewBox', '0 0 24 24')
    const path = document.createElementNS('http://www.w3.org/2000/svg', 'path')
    path.setAttribute('stroke-linecap', 'round')
    path.setAttribute('stroke-linejoin', 'round')
    path.setAttribute('stroke-width', '2')
    path.setAttribute('d', 'M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-6 9l2 2 4-4')
    svg.appendChild(path)

    // Create text container
    const textDiv = document.createElement('div')

    // Create template name paragraph (use textContent to prevent XSS)
    const namePara = document.createElement('p')
    namePara.className = 'text-sm font-medium text-gray-900 dark:text-white'
    namePara.textContent = templateName // Safe: textContent escapes HTML

    // Create type/timing paragraph (use textContent to prevent XSS)
    const typePara = document.createElement('p')
    typePara.className = 'text-xs text-gray-500 dark:text-gray-400'
    typePara.textContent = `${templateType} • ${this.humanize(timing)}` // Safe: textContent escapes HTML

    textDiv.appendChild(namePara)
    textDiv.appendChild(typePara)

    contentDiv.appendChild(svg)
    contentDiv.appendChild(textDiv)

    // Create remove button
    const button = document.createElement('button')
    button.type = 'button'
    button.className = 'text-red-500 hover:text-red-700 text-sm'
    button.textContent = 'Remove'
    button.setAttribute('data-action', 'service-job-forms#removeForm')

    // Create hidden fields (values are safe as they're attributes, not innerHTML)
    const hiddenTemplate = document.createElement('input')
    hiddenTemplate.type = 'hidden'
    hiddenTemplate.name = `service[service_job_forms_attributes][${this.formIndex}][job_form_template_id]`
    hiddenTemplate.value = templateId

    const hiddenTiming = document.createElement('input')
    hiddenTiming.type = 'hidden'
    hiddenTiming.name = `service[service_job_forms_attributes][${this.formIndex}][timing]`
    hiddenTiming.value = timing

    const hiddenRequired = document.createElement('input')
    hiddenRequired.type = 'hidden'
    hiddenRequired.name = `service[service_job_forms_attributes][${this.formIndex}][required]`
    hiddenRequired.value = 'false'

    // Assemble the element
    div.appendChild(contentDiv)
    div.appendChild(button)
    div.appendChild(hiddenTemplate)
    div.appendChild(hiddenTiming)
    div.appendChild(hiddenRequired)

    return div
  }

  humanize(str) {
    return str
      .replace(/_/g, ' ')
      .replace(/\b\w/g, char => char.toUpperCase())
  }
}
