# 🔥 BizBlasts Hotwire Setup Documentation

## Overview

BizBlasts uses a modern Hotwire stack with enhanced features for multi-tenant architecture:

- **Rails 8.0.2** with latest Hotwire integration
- **Stimulus 3.2.2** with auto-discovery and manual registration
- **Turbo 8.0.5** with tenant-aware navigation
- **Custom tenant utilities** for subdomain management

## 🎯 Stimulus Configuration

### Auto-Discovery + Manual Registration

Our setup combines the best of both worlds:

```javascript
// Manual registration for core controllers (guaranteed loading)
application.register("page-editor", PageEditorController)
application.register("dropdown", DropdownController)
// ... other core controllers

// Auto-discovery for additional controllers (compatible approach)
const controllersToDiscover = [
  { name: 'hello', path: './controllers/hello_controller' }
  // Add more controllers here as needed
];
```

### Controller Naming Conventions

| File Path | Controller Identifier |
|-----------|----------------------|
| `controllers/hello_controller.js` | `hello` |
| `controllers/admin/user_controller.js` | `admin--user` |
| `controllers/business_manager/booking_controller.js` | `business-manager--booking` |

### Creating New Controllers

**Option 1: Manual Registration (Recommended for critical controllers)**
```javascript
// Add to application.js
import MyFeatureController from "./controllers/my_feature_controller"
application.register("my-feature", MyFeatureController)
```

**Option 2: Auto-Discovery (For optional/experimental controllers)**
```bash
# 1. Create the controller file
touch app/javascript/controllers/my_feature_controller.js

# 2. Add it to the auto-discovery list in application.js
# Edit app/javascript/application.js and add:
# { name: 'my-feature', path: './controllers/my_feature_controller.js' }
```

### Adding Controllers to Auto-Discovery

To add a new controller to auto-discovery, edit `app/javascript/application.js`:

```javascript
const controllersToDiscover = [
  { name: 'my-feature', path: './controllers/my_feature_controller.js' },
  { name: 'admin--user', path: './controllers/admin/user_controller.js' }
  // Add your new controller here
];
```

**Note:** The `hello` controller used for testing is manually registered for reliability.

**Naming Rules:**
- File: `my_feature_controller.js` → Name: `'my-feature'`
- File: `admin/user_controller.js` → Name: `'admin--user'`
- Underscores become dashes: `_` → `-`
- Slashes become double dashes: `/` → `--`

## 🚀 Turbo Configuration

### Multi-Tenant Navigation

Our enhanced Turbo setup handles multi-tenant navigation intelligently:

```javascript
// Cross-subdomain navigation automatically uses full page loads
// Same-subdomain navigation uses Turbo for speed
document.addEventListener("turbo:before-visit", (event) => {
  if (TurboTenantHelpers.isCrossTenantNavigation(event.detail.url)) {
    event.preventDefault();
    window.location.href = event.detail.url; // Full page load
  }
});
```

### Tenant-Sensitive Data Management

Mark elements that should not be cached across tenants:

```erb
<!-- This data won't be cached when switching tenants -->
<div data-tenant-sensitive>
  Current Business: <%= current_business.name %>
</div>
```

### Form Context Enhancement

Forms automatically get tenant context:

```erb
<!-- This form will automatically get tenant context fields -->
<%= form_with model: @booking do |f| %>
  <!-- Your form fields -->
<% end %>

<!-- Results in hidden fields being added:
<input type="hidden" name="tenant_context" value="business-manager">
<input type="hidden" name="current_tenant" value="acme-corp">
-->
```

## 🛠️ Tenant Utilities

### TurboTenantHelpers Class

```javascript
// Check current environment
TurboTenantHelpers.isBusinessManagerArea() // true if in /manage/ routes
TurboTenantHelpers.isOnTenantSubdomain()   // true if on subdomain
TurboTenantHelpers.getCurrentTenant()      // returns subdomain or null

// Navigation helpers
TurboTenantHelpers.navigateToMainDomain('/pricing')
TurboTenantHelpers.navigateToTenant('acme-corp', '/dashboard')

// URL generation
TurboTenantHelpers.getMainDomainUrl('/contact')
TurboTenantHelpers.getTenantUrl('acme-corp', '/settings')
```

### Development Debugging

In development, tenant information is automatically logged:

```javascript
// Available in browser console
TenantHelpers.debugTenantInfo()

// Auto-logged on page load:
// 🏢 Tenant Debug Info
// Current Host: acme-corp.lvh.me:3000
// Is Tenant Subdomain: true
// Current Tenant: acme-corp
// Is Business Manager: false
// Main Domain URL: http://lvh.me:3000
```

## 📁 File Structure

```
app/javascript/
├── application.js              # Main entry point with auto-discovery
├── controllers/
│   ├── hello_controller.js     # Auto-discovered as "hello"
│   ├── dropdown_controller.js  # Manually registered + auto-discovered
│   └── admin/
│       └── user_controller.js  # Auto-discovered as "admin--user"
├── modules/
│   ├── turbo_tenant_helpers.js # Tenant utility functions
│   ├── customer_form_helper.js # Turbo-compatible module
│   └── ...
└── ...
```

## 🧪 Testing Auto-Discovery

Include the test component in development:

```erb
<%# In any view %>
<%= render 'shared/stimulus_test' %>
```

This will show a working example of the auto-discovered `hello` controller.

## 📝 Example Usage

### Creating a New Auto-Discovered Controller

1. **Create the controller file:**
```bash
touch app/javascript/controllers/example_controller.js
```

2. **Write your controller:**
```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["output", "input"]
  static values = { message: String }

  connect() {
    console.log("Example controller connected! 🎉")
  }

  greet() {
    const name = this.inputTarget.value || "World"
    this.outputTarget.textContent = `Hello, ${name}!`
  }
}
```

3. **Add it to auto-discovery in `app/javascript/application.js`:**
```javascript
const controllersToDiscover = [
  { name: 'example', path: './controllers/example_controller.js' }
];
```

4. **Use it in your HTML:**
```erb
<div data-controller="example">
  <input data-example-target="input" type="text" placeholder="Enter name">
  <button data-action="click->example#greet">Greet</button>
  <div data-example-target="output"></div>
</div>
```

5. **That's it!** The controller is automatically discovered and registered.

**Note:** For production-critical controllers like the `hello` test controller, consider using manual registration instead for better reliability.

## 🔧 Configuration Files

### Package.json Dependencies
```json
{
  "@hotwired/stimulus": "^3.2.2",
  "@hotwired/turbo-rails": "^8.0.5",
  "@rails/ujs": "^7.1.3-4"
}
```

### Rails Configuration
```ruby
# config/environments/development.rb
config.hosts << "lvh.me"
config.hosts << /.*\.lvh\.me/

# config/environments/production.rb
config.hosts = ["*.bizblasts.com", "bizblasts.com"]
```

## 🚨 Migration Notes

### From Previous Setup

All existing controllers continue to work with manual registration. New controllers can use auto-discovery by adding them to the `controllersToDiscover` array.

### Build System Compatibility

The auto-discovery system has been updated to work with the current build system (Bun) without requiring ES module features like `import.meta.glob()`.

### DOMContentLoaded → Turbo Compatibility

All event listeners have been converted to work with both:
```javascript
// Old (breaks with Turbo)
document.addEventListener('DOMContentLoaded', function() { ... });

// New (works with Turbo)
function initializeFeature() { ... }
document.addEventListener('DOMContentLoaded', initializeFeature);
document.addEventListener('turbo:load', initializeFeature);
```

## 🐛 Troubleshooting

### Controllers Not Loading
1. Check browser console for auto-discovery logs
2. Verify controller is added to `controllersToDiscover` array
3. Ensure controller file naming convention matches
4. Verify controller exports default class

### Import/Module Errors
- The system no longer uses `import.meta.glob()` to avoid module compatibility issues
- Controllers are loaded using dynamic imports which work with the current build system
- If you see "Cannot use 'import.meta' outside a module", ensure you're using the updated `application.js`

### Turbo Navigation Issues
1. Check if cross-subdomain navigation (should use full page load)
2. Verify tenant-sensitive elements are marked properly
3. Check browser console for Turbo event logs

### Development Debugging
```javascript
// Enable Stimulus debugging
Stimulus.debug = true

// Check registered controllers
console.log(Object.keys(Stimulus.router.modules))

// Check tenant information
TenantHelpers.debugTenantInfo()
```

## 📈 Performance Benefits

1. **Compatible Auto-Discovery**: Works with current build system without ES module features
2. **Tenant-Aware Caching**: Prevents cross-tenant data leaks
3. **Smart Navigation**: Fast Turbo within tenant, safe full loads between tenants
4. **Development Debugging**: Easy troubleshooting with detailed logging

## 🔮 Future Enhancements

- Lazy loading of controllers based on DOM presence
- Enhanced tenant-specific error handling
- Performance monitoring for cross-tenant navigation
- Advanced caching strategies for tenant-specific assets

---

*Last updated: January 2025*
*BizBlasts Technical Team* 