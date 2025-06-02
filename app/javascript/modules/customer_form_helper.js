/**
 * Customer Form Helper - Reusable JavaScript for dynamic customer form behavior
 * Handles show/hide logic for new customer fields across different forms
 */
const CustomerFormHelper = {
  
  /**
   * Initialize customer field toggling for a form
   * @param {Object} options - Configuration options
   * @param {string} options.customerSelectId - ID of the customer dropdown select
   * @param {string} options.newCustomerFieldsId - ID of the container for new customer fields
   * @param {Array} options.fieldSelectors - Array of field selectors to enable/disable
   * @param {string} options.newCustomerValue - Value that indicates "new customer" (default: 'new')
   */
  initializeCustomerToggle(options = {}) {
    const {
      customerSelectId,
      newCustomerFieldsId,
      fieldSelectors = ['input[name*="[name]"]', 'input[name*="[email]"]', 'input[name*="[phone]"]'],
      newCustomerValue = 'new'
    } = options;
    
    const customerSelect = document.getElementById(customerSelectId);
    const newCustomerFields = document.getElementById(newCustomerFieldsId);
    
    if (!customerSelect || !newCustomerFields) {
      return; // Elements not found, skip initialization
    }
    
    /**
     * Toggle visibility and validation of customer fields
     */
    function toggleCustomerFields() {
      const isNewCustomer = customerSelect.value === newCustomerValue;
      
      if (isNewCustomer) {
        // Show new customer fields
        newCustomerFields.classList.remove('hidden');
        newCustomerFields.style.display = '';
        
        // Enable required validation for specified fields
        fieldSelectors.forEach(selector => {
          const field = newCustomerFields.querySelector(selector);
          if (field) {
            field.required = true;
            field.disabled = false;
          }
        });
      } else {
        // Hide new customer fields
        newCustomerFields.classList.add('hidden');
        newCustomerFields.style.display = 'none';
        
        // Remove required validation and disable fields
        fieldSelectors.forEach(selector => {
          const field = newCustomerFields.querySelector(selector);
          if (field) {
            field.required = false;
            field.disabled = false; // Keep enabled for better UX
          }
        });
      }
    }
    
    // Initialize on page load
    toggleCustomerFields();
    
    // Handle dropdown changes
    customerSelect.addEventListener('change', toggleCustomerFields);
    
    return {
      customerSelect,
      newCustomerFields,
      toggleCustomerFields
    };
  },
  
  /**
   * Initialize standard order form customer toggle
   * Used by business manager order forms
   */
  initializeOrderForm() {
    return this.initializeCustomerToggle({
      customerSelectId: 'order_tenant_customer_id',
      newCustomerFieldsId: 'new-customer-fields'
    });
  },
  
  /**
   * Initialize standard booking form customer toggle
   * Used by public booking forms
   */
  initializeBookingForm() {
    return this.initializeCustomerToggle({
      customerSelectId: 'tenant_customer_id',
      newCustomerFieldsId: 'new-tenant-customer-fields'
    });
  },
  
  /**
   * Initialize generic booking form customer toggle
   * Used by shared booking form components
   */
  initializeGenericBookingForm() {
    return this.initializeCustomerToggle({
      customerSelectId: 'booking_customer_id',
      newCustomerFieldsId: 'new-customer-fields'
    });
  },
  
  /**
   * Auto-initialize based on detected form elements
   * Automatically detects which form pattern is being used and initializes accordingly
   */
  autoInitialize() {
    // Try different form patterns
    const patterns = [
      {
        customerSelectId: 'order_tenant_customer_id',
        newCustomerFieldsId: 'new-customer-fields'
      },
      {
        customerSelectId: 'tenant_customer_id',
        newCustomerFieldsId: 'new-tenant-customer-fields'
      },
      {
        customerSelectId: 'booking_customer_id',
        newCustomerFieldsId: 'new-customer-fields'
      },
      {
        customerSelectId: 'booking_customer_id_field',
        newCustomerFieldsId: 'booking_customer_fields_container'
      }
    ];
    
    for (const pattern of patterns) {
      const customerSelect = document.getElementById(pattern.customerSelectId);
      const newCustomerFields = document.getElementById(pattern.newCustomerFieldsId);
      
      if (customerSelect && newCustomerFields) {
        console.log(`CustomerFormHelper: Auto-initialized with pattern`, pattern);
        return this.initializeCustomerToggle(pattern);
      }
    }
    
    console.log('CustomerFormHelper: No matching form pattern found');
    return null;
  }
};

// Auto-initialize when DOM is loaded
document.addEventListener('DOMContentLoaded', function() {
  CustomerFormHelper.autoInitialize();
});

// Export for use in other modules
if (typeof module !== 'undefined' && module.exports) {
  module.exports = CustomerFormHelper;
} else if (typeof window !== 'undefined') {
  window.CustomerFormHelper = CustomerFormHelper;
} 