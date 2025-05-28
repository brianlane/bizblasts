//= require active_admin/base

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

document.addEventListener('DOMContentLoaded', function() {
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
});