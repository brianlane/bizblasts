//= require active_admin/base
//= require delete_fix

// Markdown Editor Class for ActiveAdmin
class MarkdownEditor {
  constructor() {
    this.init();
  }
  
  init() {
    // Setup immediately if DOM is ready, otherwise wait
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', () => this.setupEditor());
    } else {
      this.setupEditor();
    }
    
    // Check periodically for dynamically loaded content (ActiveAdmin navigation)
    setInterval(() => this.setupEditor(), 2000);
  }
  
  setupEditor() {
    const editor = document.querySelector('.markdown-editor');
    const toolbar = document.querySelector('.markdown-editor-toolbar');
    const preview = document.getElementById('content-preview');
    
    if (!editor || !toolbar || editor.dataset.editorInitialized) {
      return;
    }
    
    // Mark as initialized to prevent duplicate setup
    editor.dataset.editorInitialized = 'true';
    
    this.editor = editor;
    this.toolbar = toolbar;
    this.preview = preview;
    this.isPreviewMode = false;
    
    this.setupToolbarHandlers();
    this.setupKeyboardShortcuts();
    this.setupAutoResize();
  }
  
  wrapText(before, after = '', placeholder = '') {
    const start = this.editor.selectionStart;
    const end = this.editor.selectionEnd;
    const text = this.editor.value;
    const selectedText = text.substring(start, end);
    
    const replacement = selectedText ? 
      before + selectedText + after : 
      before + placeholder + after;
    
    const newText = text.substring(0, start) + replacement + text.substring(end);
    this.editor.value = newText;
    
    const newCursorPos = start + before.length + (selectedText || placeholder).length;
    this.editor.setSelectionRange(newCursorPos, newCursorPos);
    this.editor.focus();
  }
  
  insertAtLineStart(prefix) {
    const start = this.editor.selectionStart;
    const text = this.editor.value;
    const lineStart = text.lastIndexOf('\n', start - 1) + 1;
    const lineEnd = text.indexOf('\n', start);
    const currentLine = text.substring(lineStart, lineEnd === -1 ? text.length : lineEnd);
    
    const newLine = currentLine.startsWith(prefix) ? 
      currentLine.substring(prefix.length) : 
      prefix + currentLine;
    
    const before = text.substring(0, lineStart);
    const after = text.substring(lineEnd === -1 ? text.length : lineEnd);
    
    this.editor.value = before + newLine + after;
    this.editor.setSelectionRange(lineStart + prefix.length, lineStart + prefix.length);
    this.editor.focus();
  }
  
  setupToolbarHandlers() {
    const handlers = {
      'bold-btn': () => this.wrapText('**', '**', 'bold text'),
      'italic-btn': () => this.wrapText('*', '*', 'italic text'),
      'code-btn': () => this.wrapText('`', '`', 'code'),
      'h1-btn': () => this.insertAtLineStart('# '),
      'h2-btn': () => this.insertAtLineStart('## '),
      'h3-btn': () => this.insertAtLineStart('### '),
      'link-btn': () => {
        const url = prompt('Enter URL:');
        if (url) this.wrapText(`[`, `](${url})`, 'link text');
      },
      'image-btn': () => {
        const url = prompt('Enter image URL:');
        const alt = prompt('Enter alt text (optional):') || 'image';
        if (url) this.wrapText('', '', `![${alt}](${url})`);
      },
      'quote-btn': () => this.insertAtLineStart('> '),
      'codeblock-btn': () => {
        const language = prompt('Enter language (optional):') || '';
        this.wrapText(`\`\`\`${language}\n`, '\n```', 'code here');
      },
      'ul-btn': () => this.insertAtLineStart('- '),
      'ol-btn': () => this.insertAtLineStart('1. '),
      'table-btn': () => {
        const table = `| Header 1 | Header 2 | Header 3 |\n|----------|----------|----------|\n| Cell 1   | Cell 2   | Cell 3   |\n| Cell 4   | Cell 5   | Cell 6   |`;
        this.wrapText('', '', table);
      },
      'preview-btn': () => this.togglePreview()
    };
    
    Object.keys(handlers).forEach(className => {
      const button = this.toolbar.querySelector(`.${className}`);
      if (button) {
        button.addEventListener('click', (e) => {
          e.preventDefault();
          handlers[className]();
        });
      }
    });
  }
  
  /**
   * SECURITY FIX (Alert #23 - CWE-79): Escape HTML before markdown processing
   * This function escapes all HTML special characters to prevent XSS attacks.
   * By escaping BEFORE applying markdown transformations, we ensure that:
   * 1. Raw HTML/script tags cannot be injected
   * 2. Event handlers (onerror, onclick, etc.) are neutralized
   * 3. Only safe markdown-generated HTML is rendered
   */
  escapeHtml(text) {
    if (!text) return '';
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }

  /**
   * SECURITY: Sanitize URL to prevent javascript: and data: URI attacks
   * Only allows http:, https:, mailto:, and relative URLs
   * @param {string} url - URL to sanitize
   * @returns {string} - Sanitized URL or '#' if dangerous
   */
  sanitizeUrl(url) {
    if (!url) return '#';

    // Trim whitespace
    url = url.trim();

    // Decode HTML entities that might have been escaped
    const textarea = document.createElement('textarea');
    textarea.innerHTML = url;
    const decoded = textarea.value;

    // Check for dangerous protocols (case-insensitive)
    const dangerous = /^[\s]*(javascript|data|vbscript|file|about):/i;
    if (dangerous.test(decoded)) {
      console.warn('Blocked dangerous URL protocol:', decoded);
      return '#';
    }

    // Allow http:, https:, mailto:, tel:, sms:, and relative URLs
    const safe = /^(https?:|mailto:|tel:|sms:|\/|\.\/|\.\.\/|#)/i;
    if (safe.test(decoded)) {
      return url; // Return original (possibly entity-encoded) URL
    }

    // If no protocol specified, treat as relative (safe)
    if (!/^[\w]+:/.test(decoded)) {
      return url;
    }

    // Block everything else
    console.warn('Blocked unsafe URL:', decoded);
    return '#';
  }

  togglePreview() {
    const previewBtn = this.toolbar.querySelector('.preview-btn');

    if (this.isPreviewMode) {
      this.preview.style.display = 'none';
      this.editor.style.display = 'block';
      previewBtn.textContent = 'Preview';
      previewBtn.style.background = '#0066cc';
      this.isPreviewMode = false;
    } else {
      this.preview.style.display = 'block';
      this.editor.style.display = 'none';
      previewBtn.textContent = 'Edit';
      previewBtn.style.background = '#28a745';
      this.isPreviewMode = true;
      this.updatePreview();
    }
  }

  /**
   * SECURITY FIX (Alert #23 - CWE-79): DOM text reinterpreted as HTML vulnerability
   *
   * BEFORE: User input was processed with regex and directly set via innerHTML
   * AFTER:
   *   1. User input is HTML-escaped FIRST
   *   2. Markdown transformations applied
   *   3. URLs sanitized to prevent javascript:/data: URIs
   *
   * This prevents XSS attacks like:
   * - <script>alert('XSS')</script>
   * - <img src=x onerror="alert('XSS')">
   * - [link](javascript:alert('XSS'))
   * - ![img](javascript:alert('XSS'))
   *
   * The fix ensures only safe, markdown-generated HTML with safe URLs is rendered.
   */
  updatePreview() {
    if (!this.preview) return;

    // SECURITY: Escape ALL HTML special characters first
    let escaped = this.escapeHtml(this.editor.value);

    // Now apply markdown transformations on the ESCAPED content
    // This ensures only safe, markdown-generated HTML is created
    let html = escaped
      .replace(/^### (.*$)/gim, '<h3>$1</h3>')
      .replace(/^## (.*$)/gim, '<h2>$1</h2>')
      .replace(/^# (.*$)/gim, '<h1>$1</h1>')
      .replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>')
      .replace(/\*(.*?)\*/g, '<em>$1</em>')
      .replace(/`(.*?)`/g, '<code style="background: #f4f4f4; padding: 2px 4px; border-radius: 3px; font-family: monospace;">$1</code>')
      // SECURITY: Sanitize URLs in links
      .replace(/\[([^\]]+)\]\(([^)]+)\)/g, (match, text, url) => {
        const safeUrl = this.sanitizeUrl(url);
        return `<a href="${safeUrl}" target="_blank" style="color: #0066cc;">${text}</a>`;
      })
      // SECURITY: Sanitize URLs in images
      .replace(/!\[([^\]]*)\]\(([^)]+)\)/g, (match, alt, url) => {
        const safeUrl = this.sanitizeUrl(url);
        return `<img src="${safeUrl}" alt="${alt}" style="max-width: 100%; height: auto; border-radius: 4px;">`;
      })
      .replace(/```(\w+)?\n([\s\S]*?)```/g, '<pre style="background: #f8f8f8; padding: 10px; border-radius: 4px; overflow-x: auto;"><code>$2</code></pre>')
      .replace(/^> (.*$)/gim, '<blockquote style="border-left: 4px solid #ddd; margin: 0; padding-left: 16px; color: #666;">$1</blockquote>')
      .replace(/^\- (.*$)/gim, '<li>$1</li>')
      .replace(/^1\. (.*$)/gim, '<li>$1</li>')
      .replace(/\n/g, '<br>');

    // Wrap list items in ul tags
    html = html.replace(/(<li>.*?<\/li>(?:<br><li>.*?<\/li>)*)/g, '<ul style="margin: 10px 0; padding-left: 20px;">$1</ul>');
    html = html.replace(/<br><li>/g, '<li>').replace(/<\/li><br>/g, '</li>');

    // Safe to set innerHTML now - all user input escaped and URLs sanitized
    this.preview.innerHTML = html || '<em style="color: #999;">Preview will appear here...</em>';
  }
  
  setupKeyboardShortcuts() {
    this.editor.addEventListener('keydown', (e) => {
      if (e.ctrlKey || e.metaKey) {
        switch(e.key) {
          case 'b':
            e.preventDefault();
            this.wrapText('**', '**', 'bold text');
            break;
          case 'i':
            e.preventDefault();
            this.wrapText('*', '*', 'italic text');
            break;
          case 'k':
            e.preventDefault();
            this.wrapText('`', '`', 'code');
            break;
          case 'l':
            e.preventDefault();
            const url = prompt('Enter URL:');
            if (url) this.wrapText(`[`, `](${url})`, 'link text');
            break;
        }
      }
    });
  }
  
  setupAutoResize() {
    const autoResize = () => {
      // Store current scroll position and cursor position
      const scrollTop = window.pageYOffset || document.documentElement.scrollTop;
      const cursorPosition = this.editor.selectionStart;
      
      // Store the current height to check if resize is needed
      const currentHeight = this.editor.offsetHeight;
      
      // Temporarily set height to auto to get the required height
      this.editor.style.height = 'auto';
      const newHeight = this.editor.scrollHeight;
      
      // Only resize if there's a significant difference (avoids constant micro-adjustments)
      if (Math.abs(newHeight - currentHeight) > 5) {
        this.editor.style.height = newHeight + 'px';
      } else {
        // Restore original height if no significant change needed
        this.editor.style.height = currentHeight + 'px';
      }
      
      // Restore scroll position to prevent jumping
      window.scrollTo(0, scrollTop);
      
      // Restore cursor position
      this.editor.setSelectionRange(cursorPosition, cursorPosition);
    };
    
    // Use a debounced version to avoid too frequent resizing
    let resizeTimeout;
    const debouncedResize = () => {
      clearTimeout(resizeTimeout);
      resizeTimeout = setTimeout(autoResize, 100);
    };
    
    this.editor.addEventListener('input', debouncedResize);
    
    // Prevent scroll jumping on focus/click
    this.editor.addEventListener('focus', (e) => {
      e.preventDefault();
      // Don't scroll to show cursor when focusing
    });
    
    // Prevent scroll jumping when clicking to position cursor
    this.editor.addEventListener('click', (e) => {
      const scrollTop = window.pageYOffset || document.documentElement.scrollTop;
      setTimeout(() => {
        window.scrollTo(0, scrollTop);
      }, 1);
    });
    
    // Initial resize without debouncing
    autoResize();
  }
}

// Initialize markdown editor
new MarkdownEditor();

/**
 * Custom Batch Actions Fix for Active Admin
 * 
 * PROBLEM: Active Admin's batch actions were not working properly - the dropdown button
 * was not clickable and the dropdown menu was not appearing when clicked.
 * 
 * SOLUTION: This script completely replaces Active Admin's broken batch actions JavaScript
 * with a custom implementation that:
 * 
 * 1. MANUAL DROPDOWN FUNCTIONALITY
 *    - Replaces Active Admin's broken dropdown JavaScript
 *    - Handles click events on dropdown buttons
 *    - Properly toggles dropdown menu visibility
 *    - Manages dropdown positioning and styling
 * 
 * 2. COMPLETE BATCH ACTION PROCESSING
 *    - Creates custom click handlers for batch action links
 *    - Automatically builds and submits forms with proper CSRF tokens
 *    - Handles confirmation dialogs from data-confirm attributes
 *    - Processes selected checkbox values correctly
 * 
 * 3. VISUAL STATE MANAGEMENT
 *    - Enables/disables buttons based on checkbox selection
 *    - Provides visual feedback with opacity changes
 *    - Manages header checkbox (select all) functionality
 *    - Closes dropdowns when clicking outside
 * 
 * 4. CSS OVERRIDES
 *    - Forces proper positioning with !important rules
 *    - Ensures dropdowns appear above other elements (z-index: 9999)
 *    - Provides professional styling for dropdown menus
 *    - Handles disabled states properly
 * 
 * KEY SUCCESS FACTORS:
 * - Working WITH Active Admin's HTML structure instead of against it
 * - Using !important CSS rules to override Active Admin's styles
 * - Manual form creation and submission for batch actions
 * - Proper event management to prevent conflicts
 * - Enhanced positioning and z-index management
 */

function initializeActiveAdminEnhancements() {
  let isUpdating = false; // Prevent infinite loops
  
  // Function to manually initialize Active Admin dropdown functionality
  function initializeActiveAdminDropdowns() {
    const dropdownButtons = document.querySelectorAll('.dropdown_menu_button');
    
    dropdownButtons.forEach((button, index) => {
      // Remove any existing click handlers to avoid duplicates
      const newButton = button.cloneNode(true);
      button.parentNode.replaceChild(newButton, button);
      
      // Add click handler to toggle dropdown
      newButton.addEventListener('click', function(e) {
        e.preventDefault();
        e.stopPropagation();
        
        // Check if button is disabled
        if (newButton.style.pointerEvents === 'none' || newButton.classList.contains('disabled')) {
          return false;
        }
        
        // Close all other dropdowns first
        const allDropdowns = document.querySelectorAll('.dropdown_menu_list_wrapper');
        allDropdowns.forEach(dropdown => {
          if (dropdown !== newButton.parentElement.querySelector('.dropdown_menu_list_wrapper')) {
            dropdown.style.display = 'none';
          }
        });
        
        // Find the dropdown menu
        const dropdownMenu = newButton.parentElement.querySelector('.dropdown_menu_list_wrapper');
        if (dropdownMenu) {
          // Toggle visibility with enhanced positioning
          if (dropdownMenu.style.display === 'none' || !dropdownMenu.style.display) {
            // Position and style the dropdown
            dropdownMenu.style.display = 'block';
            dropdownMenu.style.position = 'absolute';
            dropdownMenu.style.top = '100%';
            dropdownMenu.style.left = '0';
            dropdownMenu.style.zIndex = '9999';
            dropdownMenu.style.minWidth = '200px';
            dropdownMenu.style.maxWidth = '300px';
            dropdownMenu.style.backgroundColor = 'white';
            dropdownMenu.style.border = '1px solid #ccc';
            dropdownMenu.style.borderRadius = '4px';
            dropdownMenu.style.boxShadow = '0 4px 8px rgba(0,0,0,0.15)';
            dropdownMenu.style.marginTop = '2px';
            
            // Ensure parent container has relative positioning
            newButton.parentElement.style.position = 'relative';
          } else {
            dropdownMenu.style.display = 'none';
          }
        }
        
        return false;
      });
    });
  }
  
  // Function to setup batch action links
  function setupBatchActionLinks() {
    const batchActionLinks = document.querySelectorAll('a.batch_action');
    
    batchActionLinks.forEach((link, index) => {
      // Remove existing handlers
      const newLink = link.cloneNode(true);
      link.parentNode.replaceChild(newLink, link);
      
      newLink.addEventListener('click', function(e) {
        // Get selected checkboxes
        const selectedCheckboxes = document.querySelectorAll('input[type="checkbox"][name="collection_selection[]"]:checked');
        const selectedIds = Array.from(selectedCheckboxes).map(cb => cb.value);
        
        if (selectedIds.length === 0) {
          alert('Please select at least one item.');
          e.preventDefault();
          return false;
        }
        
        // Get action details
        const action = newLink.getAttribute('data-action');
        const confirmMessage = newLink.getAttribute('data-confirm');
        
        // Show confirmation if required
        if (confirmMessage && !confirm(confirmMessage)) {
          e.preventDefault();
          return false;
        }
        
        // Create and submit form
        const form = document.createElement('form');
        form.method = 'POST';
        form.action = window.location.pathname + '/batch_action';
        
        // Add CSRF token
        const csrfToken = document.querySelector('meta[name="csrf-token"]');
        if (csrfToken) {
          const csrfInput = document.createElement('input');
          csrfInput.type = 'hidden';
          csrfInput.name = 'authenticity_token';
          csrfInput.value = csrfToken.getAttribute('content');
          form.appendChild(csrfInput);
        }
        
        // Add batch action
        const actionInput = document.createElement('input');
        actionInput.type = 'hidden';
        actionInput.name = 'batch_action';
        actionInput.value = action;
        form.appendChild(actionInput);
        
        // Add selected IDs
        selectedIds.forEach(id => {
          const idInput = document.createElement('input');
          idInput.type = 'hidden';
          idInput.name = 'collection_selection[]';
          idInput.value = id;
          form.appendChild(idInput);
        });
        
        // Submit form
        document.body.appendChild(form);
        form.submit();
        
        e.preventDefault();
        return false;
      });
    });
  }
  
  // Function to enable/disable batch actions based on checkbox selection
  function updateBatchActions() {
    if (isUpdating) return;
    isUpdating = true;
    
    const checkboxes = document.querySelectorAll('input[type="checkbox"][name="collection_selection[]"]');
    const headerCheckbox = document.querySelector('input[type="checkbox"][name="collection_selection_toggle_all"]');
    
    // Look for batch actions container
    const batchActionsContainer = document.querySelector('.batch_actions_selector') || 
                                 document.querySelector('.table_tools .batch_actions');
    
    let batchActionButton = null;
    let dropdownMenu = null;
    
    if (batchActionsContainer) {
      batchActionButton = batchActionsContainer.querySelector('.dropdown_menu_button');
      dropdownMenu = batchActionsContainer.querySelector('.dropdown_menu_list_wrapper');
    }
    
    let checkedCount = 0;
    checkboxes.forEach(function(checkbox) {
      if (checkbox.checked) {
        checkedCount++;
      }
    });
    
    // Enable/disable the main dropdown button
    if (batchActionButton) {
      if (checkedCount === 0) {
        batchActionButton.style.opacity = '0.5';
        batchActionButton.style.pointerEvents = 'none';
        batchActionButton.style.cursor = 'not-allowed';
        batchActionButton.classList.add('disabled');
      } else {
        batchActionButton.style.opacity = '';
        batchActionButton.style.pointerEvents = '';
        batchActionButton.style.cursor = '';
        batchActionButton.classList.remove('disabled');
      }
    }
    
    // Enable/disable the dropdown menu container
    if (dropdownMenu) {
      if (checkedCount === 0) {
        dropdownMenu.style.opacity = '0.5';
        dropdownMenu.style.pointerEvents = 'none';
        dropdownMenu.style.display = 'none'; // Close dropdown if no items selected
      } else {
        dropdownMenu.style.opacity = '';
        dropdownMenu.style.pointerEvents = '';
      }
    }
    
    // Update header checkbox state
    if (headerCheckbox) {
      if (checkedCount === 0) {
        headerCheckbox.checked = false;
        headerCheckbox.indeterminate = false;
      } else if (checkedCount === checkboxes.length) {
        headerCheckbox.checked = true;
        headerCheckbox.indeterminate = false;
      } else {
        headerCheckbox.checked = false;
        headerCheckbox.indeterminate = true;
      }
    }
    
    setTimeout(() => { isUpdating = false; }, 100);
  }
  
  // Function to handle header checkbox click
  function handleHeaderCheckboxClick() {
    const headerCheckbox = document.querySelector('input[type="checkbox"][name="collection_selection_toggle_all"]');
    const checkboxes = document.querySelectorAll('input[type="checkbox"][name="collection_selection[]"]');
    
    if (headerCheckbox) {
      headerCheckbox.addEventListener('change', function() {
        checkboxes.forEach(function(checkbox) {
          checkbox.checked = headerCheckbox.checked;
        });
        setTimeout(updateBatchActions, 50);
      });
    }
  }
  
  // Function to handle individual checkbox clicks
  function handleIndividualCheckboxes() {
    const checkboxes = document.querySelectorAll('input[type="checkbox"][name="collection_selection[]"]');
    
    checkboxes.forEach(function(checkbox, index) {
      checkbox.addEventListener('change', function() {
        setTimeout(updateBatchActions, 50);
      });
    });
  }
  
  // Function to add enhanced custom CSS
  function addCustomCSS() {
    if (document.getElementById('batch-actions-fix-css')) return;
    
    const style = document.createElement('style');
    style.id = 'batch-actions-fix-css';
    style.textContent = `
      /* Enhanced CSS for batch actions */
      .batch_actions_selector {
        position: relative !important;
      }
      
      .batch_actions_selector .dropdown_menu_button.disabled {
        opacity: 0.5 !important;
        pointer-events: none !important;
        cursor: not-allowed !important;
      }
      
      .batch_actions_selector .dropdown_menu_list_wrapper[style*="pointer-events: none"] {
        opacity: 0.5 !important;
      }
      
      /* Force dropdown menu to be visible and properly positioned */
      .batch_actions_selector .dropdown_menu_list_wrapper[style*="display: block"] {
        display: block !important;
        position: absolute !important;
        top: 100% !important;
        left: 0 !important;
        background: white !important;
        border: 1px solid #ccc !important;
        border-radius: 4px !important;
        box-shadow: 0 4px 8px rgba(0,0,0,0.15) !important;
        z-index: 9999 !important;
        min-width: 200px !important;
        max-width: 300px !important;
        margin-top: 2px !important;
      }
      
      .batch_actions_selector .dropdown_menu_list {
        list-style: none !important;
        margin: 0 !important;
        padding: 0 !important;
        background: white !important;
      }
      
      .batch_actions_selector .dropdown_menu_list li {
        margin: 0 !important;
        padding: 0 !important;
        border-bottom: 1px solid #eee !important;
      }
      
      .batch_actions_selector .dropdown_menu_list li:last-child {
        border-bottom: none !important;
      }
      
      .batch_actions_selector .dropdown_menu_list a {
        display: block !important;
        padding: 10px 15px !important;
        text-decoration: none !important;
        color: #333 !important;
        font-size: 14px !important;
        line-height: 1.4 !important;
        transition: background-color 0.2s ease !important;
      }
      
      .batch_actions_selector .dropdown_menu_list a:hover {
        background-color: #f5f5f5 !important;
        color: #000 !important;
      }
      
      .batch_actions_selector .dropdown_menu_list_wrapper {
        z-index: 9999 !important;
      }
    `;
    document.head.appendChild(style);
  }
  
  // Initialize batch actions
  function initializeBatchActions() {
    addCustomCSS();
    initializeActiveAdminDropdowns();
    setupBatchActionLinks();
    handleHeaderCheckboxClick();
    handleIndividualCheckboxes();
    setTimeout(updateBatchActions, 100);
  }
  
  // Run initialization
  initializeBatchActions();
  
  // Re-run after AJAX requests
  let ajaxTimeout;
  document.addEventListener('ajax:complete', function() {
    clearTimeout(ajaxTimeout);
    ajaxTimeout = setTimeout(initializeBatchActions, 500);
  });
  
  // Delayed initialization
  setTimeout(initializeBatchActions, 1000);
  
  // Mutation observer for checkbox changes
  if (window.MutationObserver) {
    let mutationTimeout;
    const observer = new MutationObserver(function(mutations) {
      let shouldUpdate = false;
      
      mutations.forEach(function(mutation) {
        if (mutation.type === 'attributes' && 
            mutation.target.type === 'checkbox' && 
            mutation.target.name && 
            mutation.target.name.includes('collection_selection')) {
          shouldUpdate = true;
        }
      });
      
      if (shouldUpdate) {
        clearTimeout(mutationTimeout);
        mutationTimeout = setTimeout(updateBatchActions, 100);
      }
    });
    
    observer.observe(document.body, {
      attributes: true,
      attributeFilter: ['checked'],
      subtree: true
    });
  }
  
  // Close dropdowns when clicking outside
  document.addEventListener('click', function(e) {
    if (!e.target.closest('.batch_actions_selector')) {
      const openDropdowns = document.querySelectorAll('.dropdown_menu_list_wrapper[style*="display: block"]');
      openDropdowns.forEach(dropdown => {
        dropdown.style.display = 'none';
      });
    }
  });
}

// Initialize on both DOMContentLoaded and turbo:load for Turbo compatibility
document.addEventListener('DOMContentLoaded', initializeActiveAdminEnhancements);
document.addEventListener('turbo:load', initializeActiveAdminEnhancements);

// Custom confirm + POST helper for ActiveAdmin member links
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

document.addEventListener('DOMContentLoaded', initializeAAConfirmPostLinks);
document.addEventListener('turbo:load', initializeAAConfirmPostLinks);
