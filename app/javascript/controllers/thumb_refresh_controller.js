import { Controller } from "@hotwired/stimulus"

// Shopify processes a new product's image for a few seconds after the seed.
// While any thumbnail is still pending, quietly reload this Turbo frame
// (only the "Last run" card) a few times, then stop.
export default class extends Controller {
  static values = {
    url: String,
    interval: { type: Number, default: 3000 },
    max: { type: Number, default: 4 }
  }

  connect() {
    this.attempts = 0
    this.onLoad = () => this.schedule()
    this.element.addEventListener("turbo:frame-load", this.onLoad)
    this.schedule()
  }

  disconnect() {
    clearTimeout(this.timer)
    this.element.removeEventListener("turbo:frame-load", this.onLoad)
  }

  schedule() {
    clearTimeout(this.timer)
    if (!this.element.querySelector(".thumb-pending")) return
    if (this.attempts >= this.maxValue) return this.giveUp()

    this.timer = setTimeout(() => {
      this.attempts++
      if (this.element.src) this.element.reload()
      else this.element.src = this.urlValue
    }, this.intervalValue)
  }

  // Leave a plain grey box instead of a spinner that never finishes.
  giveUp() {
    this.element.querySelectorAll(".thumb-pending").forEach((el) => {
      el.classList.remove("thumb-pending")
      el.removeAttribute("title")
    })
  }
}
