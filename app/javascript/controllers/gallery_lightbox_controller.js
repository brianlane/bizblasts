import { Controller } from "@hotwired/stimulus"

// Gallery lightbox controller for fullscreen image viewing
export default class extends Controller {
  static targets = ["modal", "image", "title", "description", "counter", "prevBtn", "nextBtn", "info"]

  connect() {
    this.photos = this.getPhotosData()
    this.currentIndex = 0
  }

  open(event) {
    const photoIndex = parseInt(event.currentTarget.dataset.photoIndex)
    this.currentIndex = photoIndex
    this.showPhoto()
    this.modalTarget.classList.remove("hidden")
    this.modalTarget.classList.add("flex")
    document.body.style.overflow = "hidden"
  }

  close(event) {
    // Only close if clicking the backdrop or close button
    if (event.target === this.modalTarget || event.currentTarget.dataset.action?.includes("close")) {
      this.modalTarget.classList.add("hidden")
      this.modalTarget.classList.remove("flex")
      document.body.style.overflow = ""
    }
  }

  stopPropagation(event) {
    // Prevent clicks on the image from closing the modal
    event.stopPropagation()
  }

  next() {
    this.currentIndex = (this.currentIndex + 1) % this.photos.length
    this.showPhoto()
  }

  prev() {
    this.currentIndex = (this.currentIndex - 1 + this.photos.length) % this.photos.length
    this.showPhoto()
  }

  handleKeyboard(event) {
    if (!this.modalTarget.classList.contains("hidden")) {
      switch (event.key) {
        case "Escape":
          this.close({ target: this.modalTarget })
          break
        case "ArrowRight":
          this.next()
          break
        case "ArrowLeft":
          this.prev()
          break
      }
    }
  }

  showPhoto() {
    const photo = this.photos[this.currentIndex]

    // Update image
    this.imageTarget.src = photo.url
    this.imageTarget.alt = photo.title || `Photo ${this.currentIndex + 1}`

    // Update title and description
    if (this.hasTitleTarget) {
      this.titleTarget.textContent = photo.title || ""
      this.titleTarget.classList.toggle("hidden", !photo.title)
    }

    if (this.hasDescriptionTarget) {
      this.descriptionTarget.textContent = photo.description || ""
      this.descriptionTarget.classList.toggle("hidden", !photo.description)
    }

    // Update counter
    if (this.hasCounterTarget) {
      this.counterTarget.textContent = `${this.currentIndex + 1} / ${this.photos.length}`
    }

    // Show/hide navigation buttons
    if (this.photos.length <= 1) {
      if (this.hasPrevBtnTarget) this.prevBtnTarget.classList.add("hidden")
      if (this.hasNextBtnTarget) this.nextBtnTarget.classList.add("hidden")
    }
  }

  getPhotosData() {
    // Extract photo data from the grid only (not from featured carousel)
    // The grid section has class "grid" so we query within that container only
    const gridContainer = this.element.querySelector(".grid")
    if (!gridContainer) return []

    const photoElements = gridContainer.querySelectorAll("[data-photo-index]")
    return Array.from(photoElements).map((el) => {
      const img = el.querySelector("img")
      const titleEl = el.querySelector("h4")

      return {
        url: img.src.replace("/medium/", "/large/"), // Get large version
        title: titleEl?.textContent || "",
        description: ""
      }
    })
  }
}
