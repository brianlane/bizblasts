// Custom confirm + POST helper for ActiveAdmin member links
// Handles links with aa-post-confirm class to show confirmation and submit POST

function initializeAAConfirmPostLinks() {
  function wire(container) {
    const links = container.querySelectorAll('a.aa-post-confirm');
    links.forEach((link) => {
      // Replace existing handlers
      const cloned = link.cloneNode(true);
      link.parentNode.replaceChild(cloned, link);

      cloned.addEventListener('click', function(e) {
        e.preventDefault();
        const message = cloned.getAttribute('data-confirm');
        if (message && !window.confirm(message)) {
          return false;
        }
        // Build and submit a POST form
        const form = document.createElement('form');
        form.method = 'POST';
        form.action = cloned.getAttribute('href');
        form.style.display = 'none';
        // CSRF token
        const csrf = document.querySelector('meta[name="csrf-token"]');
        if (csrf) {
          const token = document.createElement('input');
          token.type = 'hidden';
          token.name = 'authenticity_token';
          token.value = csrf.getAttribute('content');
          form.appendChild(token);
        }
        // Method override not needed (POST), but keep compatibility hook
        const methodInput = document.createElement('input');
        methodInput.type = 'hidden';
        methodInput.name = '_method';
        methodInput.value = 'post';
        form.appendChild(methodInput);

        document.body.appendChild(form);
        form.submit();
        return false;
      });
    });
  }

  // Initial wire
  wire(document);

  // Re-wire on Turbo loads and DOM changes
  document.addEventListener('turbo:load', () => wire(document));
  document.addEventListener('DOMContentLoaded', () => wire(document));
}

// Initialize immediately if DOM is ready, otherwise wait for DOMContentLoaded
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', initializeAAConfirmPostLinks);
} else {
  // DOM is already loaded, initialize now
  initializeAAConfirmPostLinks();
}

// Handle Turbo navigation
document.addEventListener('turbo:load', initializeAAConfirmPostLinks);

export default initializeAAConfirmPostLinks;
