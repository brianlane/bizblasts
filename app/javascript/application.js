// Application JavaScript
// Your custom JavaScript can be added here
import '@hotwired/turbo-rails';

// Configure Stimulus with auto-discovery and manual registration
import { Application } from '@hotwired/stimulus';

const application = Application.start();

// Configure Turbo strategically for multi-domain app
import { Turbo } from '@hotwired/turbo-rails';
Turbo.session.drive = true;

// Import tenant-aware utilities
import TurboTenantHelpers from './modules/turbo_tenant_helpers';

// Enhanced Turbo configuration for multi-tenant architecture
function initializeTurboConfiguration() {
  if (typeof Turbo !== 'undefined') {
    // Disable prefetch functionality globally to prevent hover requests
    const prefetchElements = document.querySelectorAll('[data-turbo-prefetch]');
    prefetchElements.forEach(el => el.setAttribute('data-turbo-prefetch', 'false'));
  }
}

// Tenant-specific Turbo configuration and navigation handling
function setupTenantSpecificTurboHandlers() {
  // Before visit handler for tenant-specific logic
  document.addEventListener('turbo:before-visit', (event) => {
    const url = new URL(event.detail.url);
    const currentHost = window.location.host;
    const targetHost = url.host;
    
    // Add tenant-specific headers for business manager routes
    if (event.detail.url.includes('/manage/')) {
      // Business manager specific logic
      //console.log('Navigating to business manager area');
      
      // Add custom headers if needed for tenant context
      if (event.detail.fetchOptions) {
        event.detail.fetchOptions.headers = event.detail.fetchOptions.headers || {};
        event.detail.fetchOptions.headers['X-Tenant-Context'] = 'business-manager';
      }
    }
    
    // Handle cross-subdomain navigation using tenant helpers
    if (TurboTenantHelpers.isCrossTenantNavigation(event.detail.url)) {
      // For cross-subdomain navigation, disable Turbo and use regular navigation
      // This ensures proper tenant context switching
      event.preventDefault();
      window.location.href = event.detail.url;
    }
  });
  
  // Before cache handler for tenant-specific cache management
  document.addEventListener('turbo:before-cache', (event) => {
    // Use tenant helpers to properly manage sensitive data
    TurboTenantHelpers.clearTenantSensitiveData();
  });
  
  // After visit handler for tenant context restoration
  document.addEventListener('turbo:visit', (event) => {
    // Use tenant helpers to restore sensitive data
    TurboTenantHelpers.restoreTenantSensitiveData();
  });
  
  // Handle form submissions with tenant context
  document.addEventListener('turbo:submit-start', (event) => {
    const form = event.target;
    
    // Use tenant helpers to add appropriate context
    TurboTenantHelpers.addTenantContextToForm(form);
  });
  
  // Enhanced error handling for tenant-specific errors
  document.addEventListener('turbo:fetch-request-error', (event) => {
    const { fetchOptions, url, request } = event.detail;
    
    // Handle tenant-specific errors (e.g., subdomain not found)
    if (request.response?.status === 404 && url.includes('.lvh.me')) {
      console.warn('Tenant subdomain not found, redirecting to main domain');
      // Could redirect to main domain or show tenant selection
    }
  });
}

// Disable wheel scrolling on number inputs to prevent accidental value changes
function disableWheelOnNumberInputs() {
  document.querySelectorAll('input[type="number"][data-disable-wheel]').forEach(function(input) {
    input.addEventListener('wheel', function(e) {
      e.preventDefault();
    }, { passive: false });
  });
}

// Initialize on both DOMContentLoaded and turbo:load for Turbo compatibility
document.addEventListener('DOMContentLoaded', function() {
  initializeTurboConfiguration();
  disableWheelOnNumberInputs();
});
document.addEventListener('turbo:load', function() {
  initializeTurboConfiguration();
  disableWheelOnNumberInputs();
});

// Initialize tenant-specific handlers once
document.addEventListener('DOMContentLoaded', setupTenantSpecificTurboHandlers);

// Import and register all controllers manually
import PageEditorController from './controllers/page_editor_controller';
import ThemeEditorController from './controllers/theme_editor_controller'; 
import TemplateBrowserController from './controllers/template_browser_controller';
import EditSectionController from './controllers/edit_section_controller';
import NavbarController from './controllers/navbar_controller';
import DropdownController from './controllers/dropdown_controller';
import CustomerDropdownController from './controllers/customer_dropdown_controller';
import ProductVariantsController from './controllers/product_variants_controller';
import ServiceFormController from './controllers/service_form_controller';
import SortableController from './controllers/sortable_controller';
import HelloController from './controllers/hello_controller';
import ServiceVariantsController from './controllers/service_variants_controller';
import DropdownUpdaterController from './controllers/dropdown_updater_controller';
import ServiceAvailabilityController from './controllers/service_availability_controller';
import GoogleBusinessSearchController from './controllers/google_business_search_controller';
import QrPaymentController from './controllers/qr_payment_controller';
import PlaceIdLookupController from './controllers/place_id_lookup_controller';
import EnhancedLayoutSelectorController from './controllers/enhanced_layout_selector_controller';
import PhotoUploadController from './controllers/photo_upload_controller';
import GalleryManagerController from './controllers/gallery_manager_controller';
import GalleryLightboxController from './controllers/gallery_lightbox_controller';
import GalleryCarouselController from './controllers/gallery_carousel_controller';
import HeroVideoController from './controllers/hero_video_controller';

application.register('page-editor', PageEditorController);
application.register('theme-editor', ThemeEditorController);
application.register('template-browser', TemplateBrowserController);
application.register('edit-section', EditSectionController);
application.register('navbar', NavbarController);
application.register('dropdown', DropdownController);
application.register('customer-dropdown', CustomerDropdownController);
application.register('product-variants', ProductVariantsController);
application.register('service-form', ServiceFormController);
application.register('sortable', SortableController);
application.register('hello', HelloController);
application.register('service-variants', ServiceVariantsController);
application.register('dropdown-updater', DropdownUpdaterController);
application.register('service-availability', ServiceAvailabilityController);
application.register('google-business-search', GoogleBusinessSearchController);
application.register('qr-payment', QrPaymentController);
application.register('place-id-lookup', PlaceIdLookupController);
application.register('enhanced-layout-selector', EnhancedLayoutSelectorController);
application.register('photo-upload', PhotoUploadController);
application.register('gallery-manager', GalleryManagerController);
application.register('gallery-lightbox', GalleryLightboxController);
application.register('gallery-carousel', GalleryCarouselController);
application.register('hero-video', HeroVideoController);

// Additional controllers for estimates feature
import DatePickerController from "./controllers/date_picker_controller"
import DynamicLineItemsController from "./controllers/dynamic_line_items_controller"

application.register("date-picker", DatePickerController)
application.register("dynamic-line-items", DynamicLineItemsController)

// Auto-discovery for additional controllers (compatible approach)
// This will automatically discover and register any controllers not manually registered above
function autoDiscoverControllers() {
  try {
    // List of controllers to auto-discover (add new controllers here)
    const controllersToDiscover = [
      // { name: 'example', path: './controllers/example_controller.js' },
      // { name: 'admin--user', path: './controllers/admin/user_controller.js' }
    ];
    
    // Get list of manually registered controllers to avoid duplicates
    const manuallyRegistered = new Set([
      'page-editor', 'theme-editor', 'template-browser', 'edit-section',
      'navbar', 'dropdown', 'customer-dropdown', 'product-variants', 'service-form', 'sortable', 'hello',
      'service-variants', 'dropdown-updater', 'service-availability', 'google-business-search', 'qr-payment',
      'place-id-lookup', 'enhanced-layout-selector', 'photo-upload', 'gallery-manager', 'gallery-lightbox', 'gallery-carousel',
      'hero-video', 'date-picker', 'dynamic-line-items'
    ]);
    
    // Dynamically import and register each controller
    controllersToDiscover.forEach(async ({ name, path }) => {
      if (!manuallyRegistered.has(name)) {
        try {
          const module = await import(path);
          if (module.default) {
            application.register(name, module.default);
            //console.log(`Auto-registered Stimulus controller: ${name}`);
          }
        } catch (importError) {
          // Controller file doesn't exist, skip silently
          console.debug(`Controller ${name} not found at ${path}, skipping auto-registration`);
        }
      }
    });
  } catch (error) {
    console.warn('Auto-discovery of Stimulus controllers failed:', error);
    // Fallback gracefully - manual registration will still work
  }
}

// Run auto-discovery
autoDiscoverControllers();

// Enhanced Stimulus configuration for development
if (typeof window !== 'undefined') {
  // Check if we're in development environment more robustly
  const isDev = (typeof process !== 'undefined' && process.env && process.env.NODE_ENV === 'development') ||
                (window.location && (window.location.hostname.includes('lvh.me') || window.location.hostname === 'localhost'));
  
  // Enable debug mode in development
  application.debug = isDev;
  application.warnings = isDev;
  
  // Expose Stimulus application globally for debugging
  window.Stimulus = application;
  
  // Add helpful debugging info in development
  if (application.debug) {
    console.log('Stimulus application started with debug mode enabled');
    console.log('Available controllers:', Object.keys(application.router.modules));
    
    // Log when controllers connect/disconnect
    const originalRegister = application.register.bind(application);
    application.register = function(identifier, controllerConstructor) {
      console.log(`Registering Stimulus controller: ${identifier}`);
      return originalRegister(identifier, controllerConstructor);
    };
  }
}

// Rails UJS functionality for method: delete, etc.
import Rails from '@rails/ujs';
Rails.start();

// Application JavaScript
import './modules/availability_manager';
import './modules/booking_form_helper';
import './modules/customer_form_helper';
import './modules/customer_form_validation';
import './modules/policy_acceptance';
import './modules/category_showcase';
import './modules/copy_link';
import './modules/website_hover';
import './modules/promo_code_handler';
import './domain_status_checker';
import './cart';
import 'trix';
import '@rails/actiontext';
