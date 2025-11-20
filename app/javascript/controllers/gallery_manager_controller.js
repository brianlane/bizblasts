import { Controller } from "@hotwired/stimulus"

// Gallery manager controller for management UI
export default class extends Controller {
  openLinkModal(event) {
    event.preventDefault()
    const modal = document.getElementById("link_images_modal")
    if (modal) {
      modal.classList.remove("hidden")
      document.body.style.overflow = "hidden"
    }
  }

  closeLinkModal() {
    const modal = document.getElementById("link_images_modal")
    if (modal) {
      modal.classList.add("hidden")
      document.body.style.overflow = ""
    }
  }

  toggleReorderMode(event) {
    const enabled = event.target.checked
    const grid = document.getElementById("gallery_photos_grid")
    const sortableHandles = grid.querySelectorAll(".sortable-handle")

    if (enabled) {
      // Show drag handles
      sortableHandles.forEach((handle) => {
        handle.classList.remove("hidden")
        handle.classList.add("flex")
      })
      grid.classList.add("sortable-enabled")
    } else {
      // Hide drag handles
      sortableHandles.forEach((handle) => {
        handle.classList.add("hidden")
        handle.classList.remove("flex")
      })
      grid.classList.remove("sortable-enabled")
    }
  }

  changeView(event) {
    const view = event.target.value
    const grid = document.getElementById("gallery_photos_grid")

    if (view === "list") {
      grid.classList.remove("grid", "grid-cols-2", "md:grid-cols-3", "lg:grid-cols-4", "xl:grid-cols-5")
      grid.classList.add("space-y-4")
    } else {
      grid.classList.add("grid", "grid-cols-2", "md:grid-cols-3", "lg:grid-cols-4", "xl:grid-cols-5")
      grid.classList.remove("space-y-4")
    }
  }

  editPhoto(event) {
    const photoId = event.currentTarget.dataset.photoId
    // TODO: Open edit modal or inline edit
    console.log("Edit photo:", photoId)
  }
}
