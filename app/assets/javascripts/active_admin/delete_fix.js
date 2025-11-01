// Delete Fix Module for ActiveAdmin
// Handles DELETE method links with confirmation dialogs and CSRF tokens

function initializeDeleteFix() {
  // Remove existing listeners to prevent duplicates
  const existingListener = document._deleteFixListener;
  if (existingListener) {
    document.removeEventListener('click', existingListener);
  }

  function handleDeleteClick(event) {
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
    const csrfParam = document.querySelector('meta[name="csrf-param"]');
    const csrfToken = document.querySelector('meta[name="csrf-token"]');

    if (csrfParam && csrfToken) {
      const tokenInput = document.createElement('input');
      tokenInput.type = 'hidden';
      tokenInput.name = csrfParam.getAttribute('content');
      tokenInput.value = csrfToken.getAttribute('content');
      form.appendChild(tokenInput);
    }

    // Submit the form to perform the delete action
    document.body.appendChild(form);
    form.submit();
  }

  // Store reference to listener for cleanup
  document._deleteFixListener = handleDeleteClick;
  document.addEventListener('click', handleDeleteClick);
}

// Initialize immediately if DOM is ready, otherwise wait for DOMContentLoaded
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', initializeDeleteFix);
} else {
  // DOM is already loaded, initialize now
  initializeDeleteFix();
}

// Handle Turbo navigation
document.addEventListener('turbo:load', initializeDeleteFix);
