/**
 * Shared helper functions for booking forms
 */
const BookingFormHelper = {
  /**
   * SECURITY: Escape HTML to prevent XSS attacks
   * @param {string} text - Text to escape
   * @returns {string} - HTML-escaped text
   */
  escapeHtml(text) {
    if (!text) return '';
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  },
  /**
   * Populate form fields with provided data
   * @param {Object} formData - Object containing form values
   * @param {Object} fields - Object with form field references
   */
  populateFormFields(formData, fields) {
    const { date, time, staffId, serviceId, customerId, customerName, customerEmail, customerPhone, notes } = formData;
    
    // Set date field
    if (fields.dateField && date) {
      fields.dateField.value = date;
    }
    
    // Set time field
    if (fields.timeField && time) {
      // Format time if it's a Date object
      if (time instanceof Date) {
        const hours = String(time.getHours()).padStart(2, '0');
        const minutes = String(time.getMinutes()).padStart(2, '0');
        fields.timeField.value = `${hours}:${minutes}`;
      } else {
        fields.timeField.value = time;
      }
    }
    
    // Set staff field
    if (fields.staffField && staffId) {
      fields.staffField.value = staffId;
    }
    
    // Set service field
    if (fields.serviceField && serviceId) {
      fields.serviceField.value = serviceId;
    }
    
    // Set customer fields
    if (fields.customerIdField && customerId) {
      fields.customerIdField.value = customerId;
    }
    
    if (fields.customerNameField && customerName) {
      fields.customerNameField.value = customerName;
    }
    
    if (fields.customerEmailField && customerEmail) {
      fields.customerEmailField.value = customerEmail;
    }
    
    if (fields.customerPhoneField && customerPhone) {
      fields.customerPhoneField.value = customerPhone;
    }
    
    // Set notes field
    if (fields.notesField && notes) {
      fields.notesField.value = notes;
    }
  },
  
  /**
   * Format a date as YYYY-MM-DD
   * @param {Date} date - Date to format
   * @returns {string} Formatted date string
   */
  formatDate(date) {
    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const day = String(date.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
  },
  
  /**
   * Format a time as HH:MM
   * @param {Date} time - Time to format
   * @returns {string} Formatted time string
   */
  formatTime(time) {
    const hours = String(time.getHours()).padStart(2, '0');
    const minutes = String(time.getMinutes()).padStart(2, '0');
    return `${hours}:${minutes}`;
  },
  
  /**
   * Handle form submission errors and display them
   * SECURITY FIX: Escape HTML in error messages to prevent XSS
   * @param {Object} errors - Error object from API response
   * @param {HTMLElement} errorContainer - Container for error messages
   */
  handleSubmitError(errors, errorContainer) {
    if (!errorContainer) return;

    let errorHtml = '<ul class="error-list">';

    if (errors.messages) {
      Object.entries(errors.messages).forEach(([field, messages]) => {
        messages.forEach(message => {
          // SECURITY: Escape field name and message
          const escapedField = this.escapeHtml(field);
          const escapedMessage = this.escapeHtml(message);
          errorHtml += `<li>${escapedField} ${escapedMessage}</li>`;
        });
      });
    } else if (errors.message) {
      // SECURITY: Escape error message
      const escapedMessage = this.escapeHtml(errors.message);
      errorHtml += `<li>${escapedMessage}</li>`;
    } else {
      errorHtml += '<li>An error occurred while processing your booking. Please try again.</li>';
    }

    errorHtml += '</ul>';

    errorContainer.innerHTML = errorHtml;
    errorContainer.classList.remove('hidden');
  },
  
  /**
   * Create confirmation message after successful booking
   * SECURITY FIX: Escape HTML in booking data to prevent XSS
   * @param {Object} data - Success data with booking details
   * @param {HTMLElement} confirmationContainer - Container for confirmation message
   */
  createConfirmationMessage(data, confirmationContainer) {
    if (!confirmationContainer || !data.booking) return;

    const booking = data.booking;
    const startTime = new Date(booking.start_time);

    // SECURITY: Escape booking ID (defense in depth)
    const escapedBookingId = this.escapeHtml(String(booking.id));

    confirmationContainer.innerHTML = `
      <div class="success-message p-4 bg-green-100 text-green-800 rounded">
        <h3 class="text-lg font-bold mb-2">Booking Confirmed</h3>
        <p class="mb-1">Your appointment has been booked successfully.</p>
        <p class="mb-1">Confirmation #: ${escapedBookingId}</p>
        <p class="mb-1">Date: ${startTime.toLocaleDateString()}</p>
        <p class="mb-1">Time: ${startTime.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</p>
        <button onclick="BookingFormHelper.hideForm()" class="mt-3 bg-green-600 hover:bg-green-700 text-white font-bold py-2 px-4 rounded">Close</button>
      </div>
    `;
    confirmationContainer.classList.remove('hidden');
  },
  
  /**
   * Toggle visibility of the form overlay
   * @param {HTMLElement} overlay - Form overlay element
   * @param {boolean} show - Whether to show or hide the overlay
   */
  toggleFormOverlay(overlay, show) {
    if (!overlay) return;
    
    if (show) {
      overlay.classList.remove('hidden');
    } else {
      overlay.classList.add('hidden');
    }
  },
  
  /**
   * Hide the booking form overlay
   */
  hideForm() {
    const overlay = document.querySelector('.booking-overlay');
    if (overlay) {
      overlay.classList.add('hidden');
    }
  }
};

export default BookingFormHelper; 