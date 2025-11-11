import { Application } from "@hotwired/stimulus"
import EnhancedLayoutSelectorController from "../../../app/javascript/controllers/enhanced_layout_selector_controller"

describe("EnhancedLayoutSelectorController", () => {
  let application
  let element

  beforeEach(() => {
    document.body.innerHTML = `
      <div data-controller="enhanced-layout-selector">
        <label>
          <input type="radio" value="basic" data-enhanced-layout-selector-target="layoutInput">
        </label>
        <label>
          <input type="radio" value="enhanced" data-enhanced-layout-selector-target="layoutInput">
        </label>
        <div id="accent-wrapper" data-enhanced-layout-selector-target="accentWrapper" class="hidden">
          <div>
            <input type="hidden" data-dropdown-target="hidden" value="red">
          </div>
        </div>
      </div>
    `

    application = Application.start()
    application.register("enhanced-layout-selector", EnhancedLayoutSelectorController)
    element = document.querySelector("[data-controller='enhanced-layout-selector']")
  })

  afterEach(() => {
    application.stop()
    document.body.innerHTML = ""
  })

  it("shows the accent wrapper when enhanced layout is selected", () => {
    const [basicRadio, enhancedRadio] = element.querySelectorAll("input[type='radio']")

    enhancedRadio.checked = true
    enhancedRadio.dispatchEvent(new Event("change"))

    const wrapper = document.getElementById("accent-wrapper")
    expect(wrapper.classList.contains("hidden")).toBe(false)
  })

  it("hides the accent wrapper when basic layout is selected", () => {
    const [basicRadio, enhancedRadio] = element.querySelectorAll("input[type='radio']")

    enhancedRadio.checked = true
    enhancedRadio.dispatchEvent(new Event("change"))

    // change back to basic
    basicRadio.checked = true
    basicRadio.dispatchEvent(new Event("change"))

    const wrapper = document.getElementById("accent-wrapper")
    expect(wrapper.classList.contains("hidden")).toBe(true)
  })

  it("leaves custom dropdown visible when connected", () => {
    const customDropdown = element.querySelector("[data-enhanced-layout-selector-target='customDropdown']")
    expect(customDropdown.classList.contains("hidden")).toBe(false)
  })
})

