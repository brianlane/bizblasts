// ActiveAdmin JavaScript Entry Point
// NOTE: jQuery and jQuery UI are loaded from CDN (see layout)
// This file only contains Rails UJS, ActiveAdmin base, and our custom enhancements

// Import Rails UJS
import Rails from '@rails/ujs';

// Import ActiveAdmin base (depends on jQuery being on window)
import '@activeadmin/activeadmin';

// Import custom enhancements (these execute their initialization code)
import './active_admin/delete_fix';
import './active_admin/markdown_editor';
import './active_admin/batch_actions_fix';
import './active_admin/confirm_post_links';

// Start Rails UJS after all modules are loaded
Rails.start();

console.log('ActiveAdmin JavaScript loaded successfully');
