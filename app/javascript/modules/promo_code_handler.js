// Promo Code Handler Module
// Handles real-time promo code validation and application

class PromoCodeHandler {
  constructor() {
    this.init();
  }

  init() {    
    // Handle order promo code application
    const orderApplyButton = document.getElementById('apply_order_promo_code');
    const orderPromoField = document.getElementById('order_promo_code_field');
    const orderResultDiv = document.getElementById('order_promo_code_result');

    if (orderApplyButton && orderPromoField && orderResultDiv) {
      orderApplyButton.addEventListener('click', () => {
        this.validateOrderPromoCode(orderPromoField, orderResultDiv);
      });

      // Also allow Enter key to apply code
      orderPromoField.addEventListener('keypress', (e) => {
        if (e.key === 'Enter') {
          e.preventDefault();
          this.validateOrderPromoCode(orderPromoField, orderResultDiv);
        }
      });
    }

    // Handle booking promo code application
    const bookingApplyButton = document.getElementById('apply_promo_code');
    const bookingPromoField = document.getElementById('promo_code_field');
    const bookingResultDiv = document.getElementById('promo_code_result');

    if (bookingApplyButton && bookingPromoField && bookingResultDiv) {
      bookingApplyButton.addEventListener('click', () => {
        this.validateBookingPromoCode(bookingPromoField, bookingResultDiv);
      });

      // Also allow Enter key to apply code
      bookingPromoField.addEventListener('keypress', (e) => {
        if (e.key === 'Enter') {
          e.preventDefault();
          this.validateBookingPromoCode(bookingPromoField, bookingResultDiv);
        }
      });
    }
  }

  validateOrderPromoCode(promoField, resultDiv) {
    const code = promoField.value.trim();
    
    if (!code) {
      this.showError(resultDiv, 'Please enter a promo code');
      return;
    }

    // Get order total from the page
    const orderTotal = this.getOrderTotal();
    
    this.showLoading(resultDiv);

    // Make AJAX request to validate promo code
    fetch('/orders/validate_promo_code', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': this.getCSRFToken()
      },
      body: JSON.stringify({
        promo_code: code,
        order_total: orderTotal
      })
    })
    .then(response => response.json())
    .then(data => {
      if (data.valid) {
        this.showSuccess(resultDiv, data.message);
        this.updateOrderSummary(data.discount_amount, data.formatted_discount);
      } else {
        this.showError(resultDiv, data.error);
      }
    })
    .catch(error => {
      console.error('Error validating promo code:', error);
      this.showError(resultDiv, 'Error validating promo code. Please try again.');
    });
  }

  validateBookingPromoCode(promoField, resultDiv) {
    const code = promoField.value.trim();
    
    if (!code) {
      this.showError(resultDiv, 'Please enter a promo code');
      return;
    }

    // For bookings, we'll need to implement a similar endpoint
    // For now, show a message that the code will be validated on booking
    this.showSuccess(resultDiv, 'Promo code will be validated when you complete your booking.');
  }

  getOrderTotal() {
    // Try to find the order total from various possible locations
    const totalElements = [
      document.querySelector('[data-order-total]'),
      document.querySelector('.order-total'),
      document.querySelector('#order-total')
    ];

    for (const element of totalElements) {
      if (element) {
        const total = element.dataset.orderTotal || element.textContent;
        const numericTotal = parseFloat(total.replace(/[^0-9.]/g, ''));
        if (!isNaN(numericTotal)) {
          return numericTotal;
        }
      }
    }

    // Fallback: calculate from line items
    let total = 0;
    const lineItems = document.querySelectorAll('[data-line-item-total]');
    lineItems.forEach(item => {
      const itemTotal = parseFloat(item.dataset.lineItemTotal || item.textContent.replace(/[^0-9.]/g, ''));
      if (!isNaN(itemTotal)) {
        total += itemTotal;
      }
    });

    return total;
  }

  updateOrderSummary(discountAmount, formattedDiscount) {
    // Add discount row to order summary if it doesn't exist
    let discountRow = document.getElementById('promo-discount-row');
    
    if (!discountRow) {
      const orderSummary = document.querySelector('.order-summary, #order-summary');
      if (orderSummary) {
        discountRow = document.createElement('div');
        discountRow.id = 'promo-discount-row';
        discountRow.className = 'flex justify-between py-2 text-green-600 font-medium';
        discountRow.innerHTML = `
          <span>Promo Code Discount:</span>
          <span id="promo-discount-amount">-${formattedDiscount}</span>
        `;
        orderSummary.appendChild(discountRow);
      }
    } else {
      // Update existing discount row
      const discountAmountElement = document.getElementById('promo-discount-amount');
      if (discountAmountElement) {
        discountAmountElement.textContent = `-${formattedDiscount}`;
      }
    }

    // Update total if possible
    this.updateOrderTotal(discountAmount);
  }

  updateOrderTotal(discountAmount) {
    const totalElement = document.querySelector('[data-order-total], .order-total, #order-total');
    if (totalElement) {
      const currentTotal = parseFloat(totalElement.textContent.replace(/[^0-9.]/g, ''));
      if (!isNaN(currentTotal)) {
        const newTotal = Math.max(0, currentTotal - discountAmount);
        const formattedTotal = new Intl.NumberFormat('en-US', {
          style: 'currency',
          currency: 'USD'
        }).format(newTotal);
        
        totalElement.textContent = formattedTotal;
        if (totalElement.dataset.orderTotal) {
          totalElement.dataset.orderTotal = newTotal;
        }
      }
    }
  }

  showLoading(resultDiv) {
    resultDiv.className = 'mt-3 p-3 bg-blue-50 border border-blue-200 rounded-md';
    resultDiv.innerHTML = `
      <div class="flex items-center">
        <svg class="animate-spin -ml-1 mr-3 h-5 w-5 text-blue-500" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
          <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
          <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
        </svg>
        <span class="text-blue-700">Validating promo code...</span>
      </div>
    `;
    resultDiv.classList.remove('hidden');
  }

  showSuccess(resultDiv, message) {
    resultDiv.className = 'mt-3 p-3 bg-green-50 border border-green-200 rounded-md';
    resultDiv.innerHTML = `
      <div class="flex items-center">
        <svg class="h-5 w-5 text-green-500 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path>
        </svg>
        <span class="text-green-700">${message}</span>
      </div>
    `;
    resultDiv.classList.remove('hidden');
  }

  showError(resultDiv, message) {
    resultDiv.className = 'mt-3 p-3 bg-red-50 border border-red-200 rounded-md';
    resultDiv.innerHTML = `
      <div class="flex items-center">
        <svg class="h-5 w-5 text-red-500 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
        </svg>
        <span class="text-red-700">${message}</span>
      </div>
    `;
    resultDiv.classList.remove('hidden');
  }

  getCSRFToken() {
    const token = document.querySelector('meta[name="csrf-token"]');
    return token ? token.getAttribute('content') : '';
  }
}

// Initialize when DOM is loaded
function initPromoCodeHandler() {
  new PromoCodeHandler();
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', initPromoCodeHandler);
} else {
  // DOM is already loaded
  initPromoCodeHandler();
}

export default PromoCodeHandler; 