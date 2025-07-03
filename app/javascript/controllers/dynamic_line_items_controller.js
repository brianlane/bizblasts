import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["items", "template"]

  connect() {
    console.log("DynamicLineItemsController connected!")
    console.log("Items target:", this.itemsTarget)
    console.log("Template target:", this.templateTarget)
    // Optional: enable delete on existing items
  }

  add(event) {
    console.log("DynamicLineItemsController add() called!")
    event.preventDefault()
    const content = this.templateTarget.innerHTML.replace(/NEW_RECORD/g, new Date().getTime())
    console.log("Adding content:", content)
    this.itemsTarget.insertAdjacentHTML('beforeend', content)
  }

  remove(event) {
    console.log("DynamicLineItemsController remove() called!")
    event.preventDefault()
    const item = event.currentTarget.closest('[data-dynamic-line-items-target="item"]')
    console.log("Removing item:", item)
    // If a _destroy field exists, mark for removal
    const destroyField = item.querySelector("input[name*='_destroy']")
    if (destroyField) {
      console.log("Found destroy field, marking for removal")
      destroyField.value = '1'
      item.style.display = 'none'
    } else {
      console.log("No destroy field, removing entirely")
      // Remove entirely
      item.remove()
    }
  }
} 