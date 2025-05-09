document.addEventListener('DOMContentLoaded', function() {
  // Auto-submit the quantity form when the input changes
  const quantityForms = document.querySelectorAll('.quantity-form');
  
  quantityForms.forEach(form => {
    const quantityInput = form.querySelector('.quantity-input');
    const updateBtn = form.querySelector('.update-btn');
    
    // Hide the update button initially for a cleaner interface
    if (updateBtn) {
      updateBtn.style.display = 'none';
    }
    
    // Add event listener to auto-submit when the input loses focus
    if (quantityInput) {
      quantityInput.addEventListener('change', function() {
        form.submit();
      });
    }
  });
}); 