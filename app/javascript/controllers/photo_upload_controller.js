import { Controller } from "@hotwired/stimulus"

// Photo upload controller for drag-and-drop
export default class extends Controller {
  connect() {
    console.log("Photo upload controller connected")
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

  handleFiles(filesOrEvent) {
    console.log("handleFiles called with:", filesOrEvent)
    // Handle both Event objects (from file picker) and FileList (from drag-and-drop)
    let files
    if (filesOrEvent instanceof Event) {
      // Called from file input change event
      files = filesOrEvent.target.files
      const fileInput = filesOrEvent.target

      // Auto-submit the form when files are selected
      if (files.length > 0 && fileInput.form) {
        console.log(`${files.length} file(s) selected, submitting form...`)
        fileInput.form.requestSubmit()
      }
      return
    } else {
      // Called from drag-and-drop
      files = filesOrEvent
    }

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

      // Auto-submit the form
      if (files.length > 0 && fileInput.form) {
        fileInput.form.requestSubmit()
      }
    }
  }
}
