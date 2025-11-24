import EnhancedLayoutSelectorController from "../../../app/javascript/controllers/enhanced_layout_selector_controller"

describe("EnhancedLayoutSelectorController", () => {
  let controller
  let element

  beforeEach(() => {
    document.body.innerHTML = `
      <div id="controller" data-controller="enhanced-layout-selector">
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

    element = document.getElementById("controller")
    controller = new EnhancedLayoutSelectorController()
    controller.element = element

    // Manually set up targets since we're not using Stimulus Application
    controller.accentWrapperTarget = element.querySelector("[data-enhanced-layout-selector-target='accentWrapper']")
    controller.layoutInputTargets = Array.from(element.querySelectorAll("[data-enhanced-layout-selector-target='layoutInput']"))
    controller.hasAccentWrapperTarget = true
  })

  afterEach(() => {
    document.body.innerHTML = ""
  })

  it("shows the accent wrapper when enhanced layout is selected", () => {
    const [basicRadio, enhancedRadio] = element.querySelectorAll("input[type='radio']")

    enhancedRadio.checked = true
    controller.toggle()

    const wrapper = document.getElementById("accent-wrapper")
    expect(wrapper.classList.contains("hidden")).toBe(false)
  })

  it("hides the accent wrapper when basic layout is selected", () => {
    const [basicRadio, enhancedRadio] = element.querySelectorAll("input[type='radio']")

    // First show it
    enhancedRadio.checked = true
    controller.toggle()

    // Verify it's shown
    let wrapper = document.getElementById("accent-wrapper")
    expect(wrapper.classList.contains("hidden")).toBe(false)

    // Then hide it by selecting basic (uncheck enhanced since they're radio buttons)
    basicRadio.checked = true
    enhancedRadio.checked = false
    controller.toggle()

    // Verify it's hidden
    wrapper = document.getElementById("accent-wrapper")
    expect(wrapper.classList.contains("hidden")).toBe(true)
  })
})

