/**
 * Customer Form Validation - Comprehensive client-side validation for customer forms
 * Validates first name, last name, email, and phone number with real-time feedback
 */
const CustomerFormValidation = {
  
  /**
   * Validation rules and patterns
   */
  rules: {
    first_name: {
      required: true,
      minLength: 2,
      pattern: /^[a-zA-Z\s\-'\.]+$/,
      message: 'First name must be at least 2 characters and contain only letters'
    },
    last_name: {
      required: true,
      minLength: 2,
      pattern: /^[a-zA-Z\s\-'\.]+$/,
      message: 'Last name must be at least 2 characters and contain only letters'
    },
    email: {
      required: true,
      pattern: /^[^\s@]+@[^\s@]+\.[^\s@]+$/,
      message: 'Please enter a valid email address'
    },
    phone: {
      required: true,
      customValidation: true,
      message: 'Please enter a valid phone number (at least 7 digits)'
    }
  },

  /**
   * Initialize validation for a form
   * @param {Object} options - Configuration options
   * @param {string} options.formSelector - CSS selector for the form
   * @param {string} options.fieldPrefix - Prefix for field names (e.g., 'tenant_customer_attributes', 'customer_attributes')
   * @param {boolean} options.realTimeValidation - Enable real-time validation (default: true)
   * @param {boolean} options.showSuccessState - Show success state for valid fields (default: true)
   */
  initializeForm(options = {}) {
    const {
      formSelector,
      fieldPrefix = '',
      realTimeValidation = true,
      showSuccessState = true
    } = options;

    const form = document.querySelector(formSelector);
    if (!form) {
      console.warn(`CustomerFormValidation: Form not found with selector "${formSelector}"`);
      return null;
    }

    const validator = {
      form,
      fieldPrefix,
      errors: {},
      
      /**
       * Get field name with prefix
       */
      getFieldName(fieldType) {
        if (fieldPrefix) {
          return `${fieldPrefix}[${fieldType}]`;
        }
        return fieldType;
      },

      /**
       * Get field element
       */
      getField(fieldType) {
        const fieldName = this.getFieldName(fieldType);
        // Try multiple patterns to find the field
        const patterns = [
          `input[name="${fieldName}"]`,
          `input[name*="[${fieldType}]"]`,
          `input[name*="tenant_customer_attributes"][name*="${fieldType}"]`,
          `input[name*="customer_attributes"][name*="${fieldType}"]`,
          `input[id*="${fieldType}"]`
        ];
        
        for (const pattern of patterns) {
          const field = form.querySelector(pattern);
          if (field) {
            return field;
          }
        }
        
        return null;
      },

      /**
       * Validate phone number with custom logic
       */
      validatePhoneNumber(phoneValue) {
        // Remove all non-digit characters to count actual digits
        const digitsOnly = phoneValue.replace(/\D/g, '');
        
        // Check if we have at least 7 digits
        if (digitsOnly.length < 7) {
          return {
            isValid: false,
            message: 'Please enter a valid phone number (at least 7 digits)'
          };
        }
        
        // Check if the format contains only allowed characters
        const allowedCharsPattern = /^[\+]?[\d\s\-\(\)\.]+$/;
        if (!allowedCharsPattern.test(phoneValue)) {
          return {
            isValid: false,
            message: 'Phone number contains invalid characters'
          };
        }
        
        // Check for reasonable maximum length (to prevent abuse)
        if (digitsOnly.length > 15) {
          return {
            isValid: false,
            message: 'Phone number is too long'
          };
        }
        
        return {
          isValid: true,
          message: ''
        };
      },

      /**
       * Validate a single field
       */
      validateField(fieldType, showFeedback = true) {
        const field = this.getField(fieldType);
        if (!field) return true;

        const rule = CustomerFormValidation.rules[fieldType];
        const value = field.value.trim();
        let isValid = true;
        let errorMessage = '';

        // Check if field is required
        if (rule.required && !value) {
          isValid = false;
          errorMessage = `${fieldType.replace('_', ' ').charAt(0).toUpperCase() + fieldType.replace('_', ' ').slice(1)} is required`;
        }
        // Check minimum length
        else if (rule.minLength && value.length < rule.minLength) {
          isValid = false;
          errorMessage = rule.message;
        }
        // Check pattern
        else if (value && rule.pattern && !rule.pattern.test(value)) {
          isValid = false;
          errorMessage = rule.message;
        }
        // Custom phone validation
        else if (fieldType === 'phone' && value && rule.customValidation) {
          const phoneValidation = this.validatePhoneNumber(value);
          if (!phoneValidation.isValid) {
            isValid = false;
            errorMessage = phoneValidation.message;
          }
        }

        if (showFeedback) {
          this.showFieldFeedback(field, isValid, errorMessage);
        }

        if (isValid) {
          delete this.errors[fieldType];
        } else {
          this.errors[fieldType] = errorMessage;
        }

        return isValid;
      },

      /**
       * Show visual feedback for a field
       */
      showFieldFeedback(field, isValid, errorMessage) {
        const fieldContainer = field.closest('div') || field.parentElement;
        
        // Remove existing feedback
        this.clearFieldFeedback(field);

        if (isValid && showSuccessState && field.value.trim()) {
          // Show success state
          field.classList.remove('border-red-300', 'focus:border-red-500', 'focus:ring-red-500');
          field.classList.add('border-green-300', 'focus:border-green-500', 'focus:ring-green-500');
          
          // Add success icon
          const successIcon = document.createElement('div');
          successIcon.className = 'absolute inset-y-0 right-0 flex items-center pr-3 pointer-events-none validation-feedback';
          successIcon.innerHTML = `
            <svg class="w-5 h-5 text-green-500" fill="currentColor" viewBox="0 0 20 20">
              <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd"/>
            </svg>
          `;
          
          if (fieldContainer.style.position !== 'relative') {
            fieldContainer.style.position = 'relative';
          }
          fieldContainer.appendChild(successIcon);
        } else if (!isValid) {
          // Show error state
          field.classList.remove('border-green-300', 'focus:border-green-500', 'focus:ring-green-500');
          field.classList.add('border-red-300', 'focus:border-red-500', 'focus:ring-red-500');
          
          // Add error icon
          const errorIcon = document.createElement('div');
          errorIcon.className = 'absolute inset-y-0 right-0 flex items-center pr-3 pointer-events-none validation-feedback';
          errorIcon.innerHTML = `
            <svg class="w-5 h-5 text-red-500" fill="currentColor" viewBox="0 0 20 20">
              <path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7 4a1 1 0 11-2 0 1 1 0 012 0zm-1-9a1 1 0 00-1 1v4a1 1 0 102 0V6a1 1 0 00-1-1z" clip-rule="evenodd"/>
            </svg>
          `;
          
          if (fieldContainer.style.position !== 'relative') {
            fieldContainer.style.position = 'relative';
          }
          fieldContainer.appendChild(errorIcon);
          
          // Add error message
          const errorElement = document.createElement('p');
          errorElement.className = 'mt-1 text-sm text-red-600 validation-feedback';
          errorElement.textContent = errorMessage;
          fieldContainer.appendChild(errorElement);
        } else {
          // Neutral state
          field.classList.remove(
            'border-red-300', 'focus:border-red-500', 'focus:ring-red-500',
            'border-green-300', 'focus:border-green-500', 'focus:ring-green-500'
          );
        }
      },

      /**
       * Clear field feedback
       */
      clearFieldFeedback(field) {
        const fieldContainer = field.closest('div') || field.parentElement;
        const feedbackElements = fieldContainer.querySelectorAll('.validation-feedback');
        feedbackElements.forEach(element => element.remove());
      },

      /**
       * Validate all fields
       */
      validateAll(showFeedback = true) {
        const fieldTypes = ['first_name', 'last_name', 'email', 'phone'];
        let isFormValid = true;

        fieldTypes.forEach(fieldType => {
          const isFieldValid = this.validateField(fieldType, showFeedback);
          if (!isFieldValid) {
            isFormValid = false;
          }
        });

        return isFormValid;
      },

      /**
       * Get all validation errors
       */
      getErrors() {
        return { ...this.errors };
      },

      /**
       * Clear all errors
       */
      clearErrors() {
        this.errors = {};
        const fieldTypes = ['first_name', 'last_name', 'email', 'phone'];
        fieldTypes.forEach(fieldType => {
          const field = this.getField(fieldType);
          if (field) {
            this.clearFieldFeedback(field);
            field.classList.remove(
              'border-red-300', 'focus:border-red-500', 'focus:ring-red-500',
              'border-green-300', 'focus:border-green-500', 'focus:ring-green-500'
            );
          }
        });
      }
    };

    // Set up real-time validation
    if (realTimeValidation) {
      const fieldTypes = ['first_name', 'last_name', 'email', 'phone'];
      fieldTypes.forEach(fieldType => {
        const field = validator.getField(fieldType);
        if (field) {
          // Validate on blur
          field.addEventListener('blur', () => {
            if (field.value.trim()) {
              validator.validateField(fieldType);
            }
          });

          // Clear errors on focus if field has value
          field.addEventListener('focus', () => {
            if (field.value.trim()) {
              validator.clearFieldFeedback(field);
            }
          });

          // Validate on input for immediate feedback
          field.addEventListener('input', () => {
            if (field.value.trim()) {
              // Debounce validation
              clearTimeout(field.validationTimeout);
              field.validationTimeout = setTimeout(() => {
                validator.validateField(fieldType);
              }, 300);
            }
          });
        }
      });
    }

    // Handle form submission
    form.addEventListener('submit', (event) => {
      const isFormValid = validator.validateAll(true);
      
      if (!isFormValid) {
        event.preventDefault();
        
        // Focus on first invalid field
        const fieldTypes = ['first_name', 'last_name', 'email', 'phone'];
        for (const fieldType of fieldTypes) {
          if (validator.errors[fieldType]) {
            const field = validator.getField(fieldType);
            if (field) {
              field.focus();
              break;
            }
          }
        }
        
        // Show validation summary
        validator.showValidationSummary();
      }
    });

    // Add validation summary method
    validator.showValidationSummary = function() {
      const existingSummary = form.querySelector('.validation-summary');
      if (existingSummary) {
        existingSummary.remove();
      }

      if (Object.keys(this.errors).length > 0) {
        const summary = document.createElement('div');
        summary.className = 'validation-summary bg-red-50 border border-red-200 rounded-md p-4 mb-4';
        summary.innerHTML = `
          <div class="flex">
            <div class="flex-shrink-0">
              <svg class="h-5 w-5 text-red-400" fill="currentColor" viewBox="0 0 20 20">
                <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd"/>
              </svg>
            </div>
            <div class="ml-3">
              <h3 class="text-sm font-medium text-red-800">Please correct the following errors:</h3>
              <ul class="mt-2 text-sm text-red-700 list-disc list-inside">
                ${Object.values(this.errors).map(error => `<li>${error}</li>`).join('')}
              </ul>
            </div>
          </div>
        `;
        
        form.insertBefore(summary, form.firstChild);
        
        // Auto-remove summary after 10 seconds
        setTimeout(() => {
          if (summary.parentNode) {
            summary.remove();
          }
        }, 10000);
      }
    };

    return validator;
  },

  /**
   * Auto-initialize validation for common form patterns
   */
  autoInitialize() {
    const formPatterns = [
      // Public booking forms - smart validation (conditional for staff/manager, always for guests)
      {
        formSelector: 'form[action*="/bookings"]',
        fieldPrefix: 'booking[tenant_customer_attributes]',
        smartValidation: true // Will check for conditional container and apply appropriate logic
      },
      // Public booking forms with /book route - smart validation (conditional for staff/manager, always for guests)
      {
        formSelector: 'form[action*="/book"]',
        fieldPrefix: 'booking[tenant_customer_attributes]',
        smartValidation: true // Will check for conditional container and apply appropriate logic
      },
      // Business manager order form - only validate when new customer fields are visible
      {
        formSelector: 'form[action*="/manage/orders"]',
        fieldPrefix: 'order[tenant_customer_attributes]',
        conditionalValidation: '#new-customer-fields'
      },
      // Public order forms (plural) - validate when new customer fields are visible
      {
        formSelector: 'form[action*="/orders"]:not([action*="/manage"])',
        fieldPrefix: 'order[tenant_customer_attributes]',
        conditionalValidation: '#new-tenant-customer-fields'
      },
      // Public order form (singular) - validate when new customer fields are visible
      {
        formSelector: 'form[action*="/order"]:not([action*="/manage"]):not([action*="/orders"])',
        fieldPrefix: 'order[tenant_customer_attributes]',
        conditionalValidation: '#new-tenant-customer-fields'
      },
      // Customer management form - always validate
      {
        formSelector: 'form[action*="/customers"]',
        fieldPrefix: ''
      },
      // Subscription form - only validate when not signed in
      {
        formSelector: 'form[action*="/subscriptions"]',
        fieldPrefix: 'customer_subscription[tenant_customer_attributes]'
      },
      // Generic booking forms by ID
      {
        formSelector: '#booking-form',
        fieldPrefix: 'booking[customer_attributes]',
        conditionalValidation: '#new-customer-fields'
      },
      // Generic order forms by ID
      {
        formSelector: '#order-form',
        fieldPrefix: 'order[tenant_customer_attributes]',
        conditionalValidation: '#new-customer-fields'
      }
    ];

    const validators = [];
    
    formPatterns.forEach(pattern => {
      const form = document.querySelector(pattern.formSelector);
      if (form) {
        const validator = this.initializeForm(pattern);
        
        if (validator && pattern.smartValidation) {
          // Smart validation: check if conditional container exists
          const conditionalContainer = form.querySelector('#new-tenant-customer-fields');
          if (conditionalContainer) {
            this.setupConditionalValidation(validator, '#new-tenant-customer-fields');
          }
          // If no conditional container, validation runs always (guest forms)
        } else if (validator && pattern.conditionalValidation) {
          // Traditional conditional validation
          this.setupConditionalValidation(validator, pattern.conditionalValidation);
        }
        
        if (validator) {
          validators.push(validator);
        }
      }
    });

    return validators;
  },

  /**
   * Setup conditional validation that only runs when certain fields are visible
   */
  setupConditionalValidation(validator, containerSelector) {
    const container = document.querySelector(containerSelector);
    if (!container) return;

    // Store original validateAll method
    const originalValidateAll = validator.validateAll.bind(validator);
    
    // Override validateAll to check visibility first
    validator.validateAll = function(showFeedback = true) {
      const isVisible = !container.classList.contains('hidden') && 
                       container.style.display !== 'none' &&
                       container.offsetParent !== null;
      
      if (!isVisible) {
        return true; // Skip validation if not visible
      }
      
      return originalValidateAll(showFeedback);
    };
  }
};

// Auto-initialize when DOM is loaded
document.addEventListener('DOMContentLoaded', function() {
  CustomerFormValidation.autoInitialize();
});

// Export for use in other modules
if (typeof module !== 'undefined' && module.exports) {
  module.exports = CustomerFormValidation;
} else if (typeof window !== 'undefined') {
  window.CustomerFormValidation = CustomerFormValidation;
} 