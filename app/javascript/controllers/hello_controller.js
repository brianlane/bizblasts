import { Controller } from "@hotwired/stimulus"

// Sample controller to demonstrate auto-discovery
// This will be automatically discovered and registered as "hello"
export default class extends Controller {
  static targets = ["name", "output"]
  
  connect() {
    console.log("Hello controller connected!")
  }
  
  greet() {
    const name = this.nameTarget.value || "World"
    this.outputTarget.textContent = `Hello, ${name}!`
  }
  
  clear() {
    this.nameTarget.value = ""
    this.outputTarget.textContent = ""
  }
} 