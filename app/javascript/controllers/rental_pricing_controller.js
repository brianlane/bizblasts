import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "durationInput",
    "quantityInput",
    "totalDisplay",
    "rateDetail",
    "depositDisplay",
    "depositRow"
  ]

  static values = {
    pricingMap: Object,
    depositPerUnit: { type: Number, default: 0 },
    currency: { type: String, default: "USD" }
  }

  connect() {
    this.formatter = new Intl.NumberFormat(undefined, {
      style: "currency",
      currency: (this.currencyValue || "USD").toUpperCase()
    })

    this.update = this.update.bind(this)

    if (this.hasDurationInputTarget) {
      this.durationInputTarget.addEventListener("change", this.update)
    }
    if (this.hasQuantityInputTarget) {
      this.quantityInputTarget.addEventListener("change", this.update)
    }

    this.update()
  }

  disconnect() {
    if (this.hasDurationInputTarget) {
      this.durationInputTarget.removeEventListener("change", this.update)
    }
    if (this.hasQuantityInputTarget) {
      this.quantityInputTarget.removeEventListener("change", this.update)
    }
  }

  update() {
    const duration = parseInt(this.durationInputTarget?.value || "0", 10)
    const quantity = Math.max(1, parseInt(this.quantityInputTarget?.value || "1", 10))
    const pricing = this.lookupPricing(duration)
    const baseTotal = pricing?.base_total || 0
    const subtotal = baseTotal * quantity
    const deposit = (this.depositPerUnitValue || 0) * quantity

    if (this.hasTotalDisplayTarget) {
      this.totalDisplayTarget.textContent = this.formatter.format(subtotal)
    }

    if (this.hasRateDetailTarget) {
      const label = pricing?.label || `${duration} mins`
      this.rateDetailTarget.textContent = `${label} × ${quantity}`
    }

    if (this.hasDepositDisplayTarget && this.hasDepositRowTarget) {
      if (deposit > 0) {
        this.depositDisplayTarget.textContent = this.formatter.format(deposit)
        this.depositRowTarget.classList.remove("hidden")
      } else {
        this.depositRowTarget.classList.add("hidden")
      }
    }
  }

  lookupPricing(duration) {
    if (!this.pricingMapValue) return null

    // Keys in JSON are strings, so check both
    return this.pricingMapValue[duration] || this.pricingMapValue[String(duration)] || null
  }
}

