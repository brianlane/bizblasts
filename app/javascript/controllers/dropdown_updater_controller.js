import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["bookLink", "viewServiceLink", "variantInput", "info", "duration", "price"]
  static values = { serviceId: String }

  update(event) {
    const variantId = event.detail.value
    const option = event.detail.element
    const price = option.dataset.price
    const duration = option.dataset.duration

    // Update info text
    if (this.hasInfoTarget) {
      this.infoTarget.textContent = `Duration: ${duration} minutes | Price: ${price}`
    }

    // Update Book Now link
    if (this.hasBookLinkTarget) {
      const url = new URL(this.bookLinkTarget.href)
      url.searchParams.set('service_variant_id', variantId)
      this.bookLinkTarget.href = url.toString()
    }

    // Update View Service link
    if (this.hasViewServiceLinkTarget) {
      const url = new URL(this.viewServiceLinkTarget.href)
      url.searchParams.set('service_variant_id', variantId)
      this.viewServiceLinkTarget.href = url.toString()
    }

    // Update duration display
    if (this.hasDurationTarget && duration) {
      this.durationTarget.textContent = `${duration} min`
    }

    // Update price display
    if (this.hasPriceTarget && price) {
      // Format price as currency
      const formattedPrice = new Intl.NumberFormat('en-US', { 
        style: 'currency', 
        currency: 'USD' 
      }).format(price)
      this.priceTarget.textContent = formattedPrice
    }
  }
} 