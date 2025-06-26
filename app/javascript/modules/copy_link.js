// Copy Link Module
// Handles copying page URLs to clipboard with user feedback

function initializeCopyLinkModule() {
  const copyButtons = document.querySelectorAll('.copy-link-btn');
  
  copyButtons.forEach(button => {
    button.addEventListener('click', async function(e) {
      e.preventDefault();
      
      const url = this.dataset.url || window.location.href;
      const originalText = this.innerHTML;
      
      try {
        // Try modern clipboard API first
        if (navigator.clipboard && navigator.clipboard.writeText) {
          await navigator.clipboard.writeText(url);
        } else {
          // Fallback for older browsers or non-secure contexts
          const textArea = document.createElement('textarea');
          textArea.value = url;
          textArea.style.position = 'fixed';
          textArea.style.left = '-999999px';
          textArea.style.top = '-999999px';
          document.body.appendChild(textArea);
          textArea.focus();
          textArea.select();
          
          if (!document.execCommand('copy')) {
            throw new Error('Fallback copy method failed');
          }
          
          document.body.removeChild(textArea);
        }
        
        // Update button text to show success
        this.innerHTML = `
          <svg class="w-5 h-5 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
          </svg>
          Link Copied
        `;
        
        // Add success styling
        this.classList.remove('bg-gray-600', 'hover:bg-gray-700');
        this.classList.add('bg-green-600', 'hover:bg-green-700');
        
        // Reset after 2 seconds
        setTimeout(() => {
          this.innerHTML = originalText;
          this.classList.remove('bg-green-600', 'hover:bg-green-700');
          this.classList.add('bg-gray-600', 'hover:bg-gray-700');
        }, 2000);
        
      } catch (err) {
        console.error('Failed to copy: ', err);
      
      // Fallback: Show error message
      this.innerHTML = `
        <svg class="w-5 h-5 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
        </svg>
        Copy Failed
      `;
      
      this.classList.remove('bg-gray-600', 'hover:bg-gray-700');
      this.classList.add('bg-red-600', 'hover:bg-red-700');
      
      // Reset after 2 seconds
      setTimeout(() => {
        this.innerHTML = originalText;
        this.classList.remove('bg-red-600', 'hover:bg-red-700');
        this.classList.add('bg-gray-600', 'hover:bg-gray-700');
      }, 2000);
    }
    });
  });
}

// Initialize on both DOMContentLoaded and turbo:load for Turbo compatibility
document.addEventListener('DOMContentLoaded', initializeCopyLinkModule);
document.addEventListener('turbo:load', initializeCopyLinkModule); 