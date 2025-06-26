import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "container", 
    "addButton", 
    "template"
  ]
  
  connect() {
    console.log("Product variants controller connected")
    this.variantCounter = 0
    this.updateVariantLabelVisibility()
    this.updateRemoveButtonVisibility()
  }

  addVariant(event) {
    event.preventDefault()
    console.log("Adding new variant")
    
    // Create unique timestamp for this variant
    const timestamp = Date.now() + this.variantCounter++
    
    // Create the variant using our template
    const newVariant = this.createVariantFromTemplate(timestamp)
    
    // Insert the new variant before the add button
    this.addButtonTarget.parentElement.insertAdjacentElement('beforebegin', newVariant)
    
    // Focus on the first input of the new variant
    const firstInput = newVariant.querySelector('input[type="text"]')
    if (firstInput) {
      firstInput.focus()
    }
    
    // Update variant label customization visibility
    this.updateVariantLabelVisibility()
    this.updateRemoveButtonVisibility()
  }

  removeVariant(event) {
    event.preventDefault()
    
    const variantField = event.target.closest('.variant-field')
    if (!variantField) {
      console.error('No variant-field parent found for Remove button')
      return
    }
    
    // Look for id field - try multiple patterns that Rails might use
    let idField = variantField.querySelector('input[name*="[id]"]')
    if (!idField) {
      // Try looking for hidden fields with id in the name
      idField = variantField.querySelector('input[type="hidden"][name*="id"]')
    }
    
    if (idField && idField.value && idField.value !== '') {
      // Check if destroy field already exists
      let destroyField = variantField.querySelector('input[name*="_destroy"]')
      
      if (!destroyField) {
        // Create hidden field for _destroy
        destroyField = document.createElement('input')
        destroyField.type = 'hidden'
        destroyField.name = idField.name.replace('[id]', '[_destroy]')
        destroyField.value = '1'
        variantField.appendChild(destroyField)
      } else {
        destroyField.value = '1'
      }
      
      // Hide instead of remove for existing records
      variantField.style.display = 'none'
      
      // Add visual feedback
      variantField.style.opacity = '0.5'
    } else {
      // For new records, just remove from DOM
      variantField.remove()
    }
    
    // Update variant label customization visibility
    this.updateVariantLabelVisibility()
    this.updateRemoveButtonVisibility()
  }

  updateVariantLabelVisibility() {
    const variantLabelSection = document.getElementById('variant-label-customization')
    if (!variantLabelSection) return
    
    // Count visible variants (not marked for destruction and not hidden)
    const visibleVariants = this.containerTarget.querySelectorAll('.variant-field').length
    const hiddenVariants = this.containerTarget.querySelectorAll('.variant-field[style*="display: none"]').length
    const destroyedVariants = this.containerTarget.querySelectorAll('.variant-field input[name*="[_destroy]"][value="1"]').length
    
    const activeVariantCount = visibleVariants - hiddenVariants - destroyedVariants
    
    // Show the customization section only if there are 2 or more variants
    if (activeVariantCount >= 2) {
      variantLabelSection.style.display = 'block'
    } else {
      variantLabelSection.style.display = 'none'
    }
  }

  updateRemoveButtonVisibility() {
    // Count visible variants (not marked for destruction and not hidden)
    const visibleVariants = this.containerTarget.querySelectorAll('.variant-field').length
    const hiddenVariants = this.containerTarget.querySelectorAll('.variant-field[style*="display: none"]').length
    const destroyedVariants = this.containerTarget.querySelectorAll('.variant-field input[name*="[_destroy]"][value="1"]').length
    
    const activeVariantCount = visibleVariants - hiddenVariants - destroyedVariants
    
    // Get all remove buttons
    const removeButtons = this.containerTarget.querySelectorAll('.remove-variant')
    
    // Show/hide remove buttons based on variant count
    removeButtons.forEach(button => {
      if (activeVariantCount <= 1) {
        button.style.display = 'none'
      } else {
        button.style.display = 'inline-flex'
      }
    })
  }

  createVariantFromTemplate(timestamp) {
    const variantDiv = document.createElement('div')
    variantDiv.className = 'variant-field bg-gray-50 border border-gray-200 rounded-lg p-4 mb-4'
    variantDiv.innerHTML = `
      <div class="flex items-center justify-between mb-4">
        <h4 class="text-md font-medium text-gray-900">Product Variant</h4>
        <button type="button" 
                class="remove-variant inline-flex items-center px-3 py-1 text-xs font-medium text-red-600 bg-red-50 hover:bg-red-100 rounded-md transition-colors"
                data-action="click->product-variants#removeVariant">
          Remove Variant
        </button>
      </div>
      
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <div>
          <label class="block text-gray-700 text-sm font-bold mb-2">Variant Name</label>
          <input type="text" name="product[product_variants_attributes][${timestamp}][name]" required placeholder="e.g., Large, Red" 
                 class="shadow appearance-none border rounded w-full py-2 px-3 text-gray-700 leading-tight focus:outline-none focus:shadow-outline focus:border-blue-500" />
        </div>
        
        <div>
          <label class="block text-gray-700 text-sm font-bold mb-2">SKU</label>
          <input type="text" name="product[product_variants_attributes][${timestamp}][sku]" placeholder="Stock Keeping Unit" 
                 class="shadow appearance-none border rounded w-full py-2 px-3 text-gray-700 leading-tight focus:outline-none focus:shadow-outline focus:border-blue-500" />
        </div>
        
        <div>
          <label class="block text-gray-700 text-sm font-bold mb-2">Price Modifier ($)</label>
          <input type="number" name="product[product_variants_attributes][${timestamp}][price_modifier]" step="0.01" placeholder="0.00" 
                 class="shadow appearance-none border rounded w-full py-2 px-3 text-gray-700 leading-tight focus:outline-none focus:shadow-outline focus:border-blue-500" />
          <p class="mt-1 text-xs text-gray-500">Positive for upcharge, negative for discount</p>
        </div>
        
        <div>
          <label class="block text-gray-700 text-sm font-bold mb-2">Stock Quantity</label>
          <input type="number" name="product[product_variants_attributes][${timestamp}][stock_quantity]" required min="0" placeholder="0" 
                 class="shadow appearance-none border rounded w-full py-2 px-3 text-gray-700 leading-tight focus:outline-none focus:shadow-outline focus:border-blue-500" />
        </div>
      </div>
      
      <div class="mt-4">
        <label class="block text-gray-700 text-sm font-bold mb-2">Options (JSON)</label>
        <textarea name="product[product_variants_attributes][${timestamp}][options]" rows="2" 
                  placeholder='e.g., {"size": "Large", "color": "Red"}' 
                  class="shadow appearance-none border rounded w-full py-2 px-3 text-gray-700 leading-tight focus:outline-none focus:shadow-outline focus:border-blue-500"></textarea>
        <p class="mt-1 text-xs text-gray-500">Enter as valid JSON for additional variant properties</p>
      </div>
    `
    return variantDiv
  }
} 