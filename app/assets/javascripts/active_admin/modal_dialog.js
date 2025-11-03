/**
 * Modern Modal Dialog Component
 *
 * A lightweight, accessible modal dialog replacement for browser prompt()
 *
 * Features:
 * - Keyboard navigation (Enter to submit, Escape to cancel)
 * - Focus trapping
 * - Accessible (ARIA labels, role attributes)
 * - Customizable styling
 * - No external dependencies
 *
 * Usage:
 *   const dialog = new ModalDialog();
 *   const url = await dialog.prompt('Enter URL:', 'https://');
 *   if (url) {
 *     // User entered a value
 *   }
 */

class ModalDialog {
  constructor() {
    this.modal = null;
    this.overlay = null;
    this.resolve = null;
  }

  /**
   * Show a prompt dialog
   * @param {string} message - The prompt message
   * @param {string} defaultValue - Default input value
   * @returns {Promise<string|null>} The entered value or null if cancelled
   */
  prompt(message, defaultValue = '') {
    return new Promise((resolve) => {
      this.resolve = resolve;
      this.createModal(message, defaultValue);
      this.show();
    });
  }

  /**
   * Create the modal DOM structure
   */
  createModal(message, defaultValue) {
    // Create overlay
    this.overlay = document.createElement('div');
    this.overlay.className = 'modal-dialog-overlay';
    this.overlay.setAttribute('role', 'presentation');

    // Create modal
    this.modal = document.createElement('div');
    this.modal.className = 'modal-dialog';
    this.modal.setAttribute('role', 'dialog');
    this.modal.setAttribute('aria-modal', 'true');
    this.modal.setAttribute('aria-labelledby', 'modal-dialog-title');

    // Modal content
    this.modal.innerHTML = `
      <div class="modal-dialog-content">
        <h3 id="modal-dialog-title" class="modal-dialog-title">${this.escapeHtml(message)}</h3>
        <input type="text" class="modal-dialog-input" value="${this.escapeHtml(defaultValue)}" aria-label="Input">
        <div class="modal-dialog-buttons">
          <button type="button" class="modal-dialog-btn modal-dialog-btn-primary" data-action="submit">
            OK
          </button>
          <button type="button" class="modal-dialog-btn modal-dialog-btn-secondary" data-action="cancel">
            Cancel
          </button>
        </div>
      </div>
    `;

    this.overlay.appendChild(this.modal);
    document.body.appendChild(this.overlay);

    // Add event listeners
    this.attachEventListeners();
  }

  /**
   * Attach event listeners
   */
  attachEventListeners() {
    const input = this.modal.querySelector('.modal-dialog-input');
    const submitBtn = this.modal.querySelector('[data-action="submit"]');
    const cancelBtn = this.modal.querySelector('[data-action="cancel"]');

    // Button clicks
    submitBtn.addEventListener('click', () => this.submit());
    cancelBtn.addEventListener('click', () => this.cancel());

    // Keyboard events
    input.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') {
        e.preventDefault();
        this.submit();
      } else if (e.key === 'Escape') {
        e.preventDefault();
        this.cancel();
      }
    });

    // Close on overlay click
    this.overlay.addEventListener('click', (e) => {
      if (e.target === this.overlay) {
        this.cancel();
      }
    });

    // Trap focus within modal
    this.modal.addEventListener('keydown', (e) => {
      if (e.key === 'Tab') {
        this.handleTabKey(e);
      }
    });
  }

  /**
   * Handle Tab key for focus trapping
   */
  handleTabKey(e) {
    const focusableElements = this.modal.querySelectorAll(
      'input, button, [tabindex]:not([tabindex="-1"])'
    );
    const firstElement = focusableElements[0];
    const lastElement = focusableElements[focusableElements.length - 1];

    if (e.shiftKey && document.activeElement === firstElement) {
      e.preventDefault();
      lastElement.focus();
    } else if (!e.shiftKey && document.activeElement === lastElement) {
      e.preventDefault();
      firstElement.focus();
    }
  }

  /**
   * Show the modal
   */
  show() {
    // Add styles if not already added
    if (!document.getElementById('modal-dialog-styles')) {
      this.injectStyles();
    }

    // Show modal with animation
    requestAnimationFrame(() => {
      this.overlay.classList.add('modal-dialog-visible');
      const input = this.modal.querySelector('.modal-dialog-input');
      input.focus();
      input.select();
    });
  }

  /**
   * Hide and cleanup the modal
   */
  hide() {
    this.overlay.classList.remove('modal-dialog-visible');
    setTimeout(() => {
      if (this.overlay && this.overlay.parentNode) {
        this.overlay.parentNode.removeChild(this.overlay);
      }
      this.modal = null;
      this.overlay = null;
    }, 200); // Match CSS transition duration
  }

  /**
   * Submit the dialog
   */
  submit() {
    const input = this.modal.querySelector('.modal-dialog-input');
    const value = input.value.trim();
    this.hide();
    if (this.resolve) {
      this.resolve(value || null);
    }
  }

  /**
   * Cancel the dialog
   */
  cancel() {
    this.hide();
    if (this.resolve) {
      this.resolve(null);
    }
  }

  /**
   * Escape HTML to prevent XSS
   */
  escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }

  /**
   * Inject modal styles into the page
   */
  injectStyles() {
    const style = document.createElement('style');
    style.id = 'modal-dialog-styles';
    style.textContent = `
      .modal-dialog-overlay {
        position: fixed;
        top: 0;
        left: 0;
        right: 0;
        bottom: 0;
        background: rgba(0, 0, 0, 0.5);
        display: flex;
        align-items: center;
        justify-content: center;
        z-index: 10000;
        opacity: 0;
        transition: opacity 0.2s ease;
      }

      .modal-dialog-overlay.modal-dialog-visible {
        opacity: 1;
      }

      .modal-dialog {
        background: white;
        border-radius: 8px;
        padding: 24px;
        min-width: 400px;
        max-width: 90%;
        box-shadow: 0 8px 24px rgba(0, 0, 0, 0.2);
        transform: translateY(-20px);
        transition: transform 0.2s ease;
      }

      .modal-dialog-overlay.modal-dialog-visible .modal-dialog {
        transform: translateY(0);
      }

      .modal-dialog-title {
        margin: 0 0 16px 0;
        font-size: 18px;
        font-weight: 600;
        color: #333;
      }

      .modal-dialog-input {
        width: 100%;
        padding: 10px 12px;
        border: 1px solid #ddd;
        border-radius: 4px;
        font-size: 14px;
        margin-bottom: 20px;
        box-sizing: border-box;
      }

      .modal-dialog-input:focus {
        outline: none;
        border-color: #5B9DD9;
        box-shadow: 0 0 0 1px #5B9DD9;
      }

      .modal-dialog-buttons {
        display: flex;
        gap: 10px;
        justify-content: flex-end;
      }

      .modal-dialog-btn {
        padding: 8px 16px;
        border: none;
        border-radius: 4px;
        font-size: 14px;
        cursor: pointer;
        transition: background-color 0.2s ease;
      }

      .modal-dialog-btn-primary {
        background: #5B9DD9;
        color: white;
      }

      .modal-dialog-btn-primary:hover {
        background: #4A8BC9;
      }

      .modal-dialog-btn-secondary {
        background: #f0f0f0;
        color: #333;
      }

      .modal-dialog-btn-secondary:hover {
        background: #e0e0e0;
      }

      .modal-dialog-btn:focus {
        outline: 2px solid #5B9DD9;
        outline-offset: 2px;
      }
    `;
    document.head.appendChild(style);
  }
}

// Export for use in other modules
if (typeof module !== 'undefined' && module.exports) {
  module.exports = ModalDialog;
}
