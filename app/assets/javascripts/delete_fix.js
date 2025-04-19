document.addEventListener('DOMContentLoaded', function() {
  document.addEventListener('click', function(event) {
    // Find if the clicked element or any of its parents is a delete link
    const deleteLink = event.target.closest('a[data-method="delete"]');
    if (!deleteLink) return;
    
    // Prevent the default link behavior
    event.preventDefault();
    
    // Handle confirmation dialog if present
    const confirmMessage = deleteLink.getAttribute('data-confirm');
    if (confirmMessage && !confirm(confirmMessage)) return;
    
    // Create a form to submit the DELETE request
    const form = document.createElement('form');
    form.method = 'POST';
    form.action = deleteLink.getAttribute('href');
    form.style.display = 'none';
    
    // Add method override for DELETE
    const methodInput = document.createElement('input');
    methodInput.type = 'hidden';
    methodInput.name = '_method';
    methodInput.value = 'delete';
    form.appendChild(methodInput);
    
    // Add CSRF token
    const csrfParam = document.querySelector('meta[name="csrf-param"]').getAttribute('content');
    const csrfToken = document.querySelector('meta[name="csrf-token"]').getAttribute('content');
    
    const tokenInput = document.createElement('input');
    tokenInput.type = 'hidden';
    tokenInput.name = csrfParam;
    tokenInput.value = csrfToken;
    form.appendChild(tokenInput);
    
    // Submit the form to perform the delete action
    document.body.appendChild(form);
    form.submit();
  });
});