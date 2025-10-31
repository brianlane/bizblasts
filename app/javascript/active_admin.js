// ActiveAdmin JavaScript Entry Point
// This file bundles all ActiveAdmin JavaScript dependencies and custom modules

// Import jQuery and expose it globally before loading additional dependencies
import $ from 'jquery';

window.$ = window.jQuery = $;

async function bootActiveAdmin() {
  try {
    // Load jQuery UI widgets after jQuery is available globally
    await Promise.all([
      import('jquery-ui/ui/widgets/datepicker'),
      import('jquery-ui/ui/widgets/dialog'),
      import('jquery-ui/ui/widgets/sortable'),
      import('jquery-ui/ui/widgets/tabs')
    ]);

    // Load the ActiveAdmin base bundle
    await import('@activeadmin/activeadmin');

    // Load custom enhancements (side-effect modules)
    await Promise.all([
      import('./active_admin/delete_fix'),
      import('./active_admin/markdown_editor'),
      import('./active_admin/batch_actions_fix'),
      import('./active_admin/confirm_post_links')
    ]);

    console.log('ActiveAdmin JavaScript loaded successfully');
  } catch (error) {
    window.__ACTIVE_ADMIN_LOAD_ERROR__ = {
      message: error?.message,
      stack: error?.stack
    };
    console.error('ActiveAdmin JavaScript failed to load', error);
  }
}

bootActiveAdmin();
