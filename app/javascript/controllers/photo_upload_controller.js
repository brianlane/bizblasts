import { Controller } from "@hotwired/stimulus"

// Photo upload controller for drag-and-drop
export default class extends Controller {
  connect() {
    this.setupDragAndDrop()
  }

  setupDragAndDrop() {
    const dropZone = this.element

    ;["dragenter", "dragover", "dragleave", "drop"].forEach((eventName) => {
      dropZone.addEventListener(eventName, this.preventDefaults, false)
    })

    ;["dragenter", "dragover"].forEach((eventName) => {
      dropZone.addEventListener(eventName, this.highlight.bind(this), false)
    })

    ;["dragleave", "drop"].forEach((eventName) => {
      dropZone.addEventListener(eventName, this.unhighlight.bind(this), false)
    })

    dropZone.addEventListener("drop", this.handleDrop.bind(this), false)
  }

  preventDefaults(e) {
    e.preventDefault()
    e.stopPropagation()
  }

  highlight() {
    this.element.classList.add("border-blue-500", "bg-blue-50")
  }

  unhighlight() {
    this.element.classList.remove("border-blue-500", "bg-blue-50")
  }

  handleDrop(e) {
    const dt = e.dataTransfer
    const files = dt.files
    this.handleFiles(files)
  }

  handleFiles(files) {
    const fileInput = this.element.querySelector('input[type="file"]')
    if (fileInput) {
      // Create a DataTransfer object and add files
      const dataTransfer = new DataTransfer()
      Array.from(files).forEach((file) => {
        if (file.type.startsWith("image/")) {
          dataTransfer.items.add(file)
        }
      })
      fileInput.files = dataTransfer.files

      // Optionally trigger form submission or show preview
      console.log(`${files.length} files ready for upload`)

      // Auto-submit if only one file
      if (files.length === 1) {
        fileInput.form.requestSubmit()
      }
    }
  }
}
