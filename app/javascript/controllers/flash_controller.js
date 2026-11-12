import { Controller } from "@hotwired/stimulus"

// Fades out and removes a flash message after a delay.
export default class extends Controller {
  static values = { delay: { type: Number, default: 5000 } }

  connect() {
    this.timeout = setTimeout(() => this.dismiss(), this.delayValue)
  }

  disconnect() {
    clearTimeout(this.timeout)
  }

  dismiss() {
    clearTimeout(this.timeout)
    if (this.element.classList.contains("flash-hide")) return
    this.element.classList.add("flash-hide")
    this.element.addEventListener("transitionend", () => this.element.remove(), { once: true })
  }
}
