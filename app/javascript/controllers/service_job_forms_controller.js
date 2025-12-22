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

    div.innerHTML = `
      <div class="flex items-center">
        <svg class="w-5 h-5 text-blue-500 mr-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-6 9l2 2 4-4" />
        </svg>
        <div>
          <p class="text-sm font-medium text-gray-900 dark:text-white">${templateName}</p>
          <p class="text-xs text-gray-500 dark:text-gray-400">${templateType} &bull; ${this.humanize(timing)}</p>
        </div>
      </div>
      <button type="button" data-action="service-job-forms#removeForm" class="text-red-500 hover:text-red-700 text-sm">
        Remove
      </button>

      <!-- Hidden fields for nested attributes -->
      <input type="hidden" name="service[service_job_forms_attributes][${this.formIndex}][job_form_template_id]" value="${templateId}">
      <input type="hidden" name="service[service_job_forms_attributes][${this.formIndex}][timing]" value="${timing}">
      <input type="hidden" name="service[service_job_forms_attributes][${this.formIndex}][required]" value="false">
    `

    return div
  }

  humanize(str) {
    return str
      .replace(/_/g, ' ')
      .replace(/\b\w/g, char => char.toUpperCase())
  }
}
