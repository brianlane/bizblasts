// app/javascript/controllers/import_progress_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "status",
    "percentage",
    "bar",
    "processed",
    "total",
    "created",
    "updated",
    "skipped",
    "errors"
  ]

  static values = {
    url: String,
    finished: Boolean
  }

  connect() {
    if (!this.finishedValue) {
      this.startPolling()
    }
  }

  disconnect() {
    this.stopPolling()
  }

  startPolling() {
    this.poll()
    this.pollingInterval = setInterval(() => this.poll(), 2000)
  }

  stopPolling() {
    if (this.pollingInterval) {
      clearInterval(this.pollingInterval)
      this.pollingInterval = null
    }
  }

  async poll() {
    try {
      const response = await fetch(this.urlValue, {
        headers: {
          "Accept": "application/json",
          "X-Requested-With": "XMLHttpRequest"
        }
      })

      if (!response.ok) {
        console.error("Failed to fetch import status")
        return
      }

      const data = await response.json()
      this.updateProgress(data)

      if (data.finished) {
        this.stopPolling()
        this.finishedValue = true
      }
    } catch (error) {
      console.error("Error polling import status:", error)
    }
  }

  updateProgress(data) {
    // Update percentage
    if (this.hasPercentageTarget) {
      this.percentageTarget.textContent = `${data.progress}%`
    }

    // Update progress bar
    if (this.hasBarTarget) {
      this.barTarget.style.width = `${data.progress}%`
    }

    // Update processed count
    if (this.hasProcessedTarget) {
      this.processedTarget.textContent = data.processed_rows
    }

    // Update total count
    if (this.hasTotalTarget) {
      this.totalTarget.textContent = data.total_rows
    }

    // Update created count
    if (this.hasCreatedTarget) {
      this.createdTarget.textContent = data.created_count
    }

    // Update updated count
    if (this.hasUpdatedTarget) {
      this.updatedTarget.textContent = data.updated_count
    }

    // Update skipped count
    if (this.hasSkippedTarget) {
      this.skippedTarget.textContent = data.skipped_count
    }

    // Update error count
    if (this.hasErrorsTarget) {
      this.errorsTarget.textContent = data.error_count
    }

    // Update status badge
    if (this.hasStatusTarget) {
      this.statusTarget.textContent = this.humanizeStatus(data.status)
      this.updateStatusBadgeClass(data.status)
    }

    // Show error link if there are errors
    this.updateErrorSection(data)
  }

  humanizeStatus(status) {
    const statusMap = {
      queued: "Queued",
      running: "Running",
      succeeded: "Succeeded",
      failed: "Failed",
      partial: "Partial"
    }
    return statusMap[status] || status
  }

  updateStatusBadgeClass(status) {
    if (!this.hasStatusTarget) return

    // Remove existing status classes
    this.statusTarget.classList.remove(
      "bg-gray-100", "text-gray-800", "border-gray-200",
      "bg-blue-100", "text-blue-800", "border-blue-200",
      "bg-green-100", "text-green-800", "border-green-200",
      "bg-yellow-100", "text-yellow-800", "border-yellow-200",
      "bg-red-100", "text-red-800", "border-red-200"
    )

    // Add appropriate classes based on status
    const classMap = {
      queued: ["bg-gray-100", "text-gray-800", "border-gray-200"],
      running: ["bg-blue-100", "text-blue-800", "border-blue-200"],
      succeeded: ["bg-green-100", "text-green-800", "border-green-200"],
      partial: ["bg-yellow-100", "text-yellow-800", "border-yellow-200"],
      failed: ["bg-red-100", "text-red-800", "border-red-200"]
    }

    const classes = classMap[status] || classMap.queued
    this.statusTarget.classList.add(...classes)
  }

  updateErrorSection(data) {
    // Find the error section (it may not exist if errors were 0 initially)
    const errorSection = this.element.querySelector("[data-error-section]")

    if (data.error_count > 0 && !errorSection) {
      // Create error section dynamically if it doesn't exist
      const errorHtml = `
        <div class="mb-6 p-4 bg-red-50 border border-red-200 rounded-lg" data-error-section>
          <div class="flex items-center">
            <svg class="w-5 h-5 text-red-400 mr-2" fill="currentColor" viewBox="0 0 20 20">
              <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd"/>
            </svg>
            <span class="text-sm text-red-800">
              ${data.error_count} error${data.error_count === 1 ? '' : 's'} occurred during import.
            </span>
            <a href="${this.urlValue.replace('/status', '/errors').replace('.json', '')}"
               class="ml-auto text-sm font-medium text-red-600 hover:text-red-800 underline">
              View details
            </a>
          </div>
        </div>
      `

      // Insert before the actions section
      const actionsSection = this.element.querySelector(".border-t")
      if (actionsSection) {
        actionsSection.insertAdjacentHTML("beforebegin", errorHtml)
      }
    }
  }
}
