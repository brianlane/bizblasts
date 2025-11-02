// ActiveAdmin JavaScript Entry Point
// NOTE: jQuery and jQuery UI are loaded from CDN (see layout)
// Rails UJS is provided by the Sprockets active_admin.js (jquery_ujs)
// This file only contains ActiveAdmin base and our custom enhancements

// Import ActiveAdmin base (depends on jQuery being on window)
import '@activeadmin/activeadmin';

// Import custom enhancements (these execute their initialization code)
import './active_admin/delete_fix';
import './active_admin/markdown_editor';
import './active_admin/batch_actions_fix';
import './active_admin/confirm_post_links';

console.log('ActiveAdmin JavaScript loaded successfully');
