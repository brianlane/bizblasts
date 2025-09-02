# BizBlasts

BizBlasts is a modern multi-tenant Rails 8 application for business websites with enhanced Hotwire integration and comprehensive testing.

## 🔥 **Latest Major Enhancement: Advanced Hotwire Setup (January 2025)**

**BizBlasts now features a state-of-the-art Hotwire implementation with:**
- ✅ **Stimulus Auto-Discovery + Manual Registration** - Best of both worlds
- ✅ **Tenant-Aware Turbo Navigation** - Smart cross-subdomain handling
- ✅ **Complete Turbo Compatibility** - All 56+ DOMContentLoaded listeners converted
- ✅ **Comprehensive Test Coverage** - 61 tests covering all JavaScript functionality
- ✅ **Production-Ready** - Optimized for Render.com deployment

**📖 See [docs/HOTWIRE_SETUP.md](docs/HOTWIRE_SETUP.md) for complete documentation**

## 🔒 **Security & Compliance (January 2025)**

**BizBlasts implements enterprise-grade security measures:**
- ✅ **Multi-Tenant Isolation** - Complete data separation between businesses
- ✅ **API Authentication** - Secure API access with key-based authentication
- ✅ **Email Enumeration Protection** - Prevents user discovery attacks
- ✅ **Audit Logging** - Comprehensive security event monitoring
- ✅ **Automated Security Alerts** - Real-time notifications for suspicious activity
- ✅ **Data Sanitization** - Automatic removal of sensitive data from logs
- ✅ **Cross-Tenant Access Prevention** - Strict authorization controls

**📖 See [Security Documentation](#security) section below for implementation details**

## 🌐 **Custom Domain CNAME Setup (Premium Feature)**

**BizBlasts Premium businesses can connect custom domains using CNAME records:**
- ✅ **Automated DNS Monitoring** - Real-time verification of CNAME configuration
- ✅ **Email-Guided Setup** - Step-by-step instructions sent to business owners
- ✅ **Multi-DNS Server Verification** - Checks across Google DNS, Cloudflare, and OpenDNS
- ✅ **Render.com Integration** - Automatic domain registration with hosting platform
- ✅ **ActiveAdmin Management** - Complete admin interface for domain lifecycle
- ✅ **Automatic SSL** - HTTPS certificates provisioned automatically
- ✅ **Tier-Based Controls** - Domain removal on tier downgrades
- ✅ **Timeout Assistance** - Troubleshooting emails when setup fails
- ✅ **Domain Change Request Interface** - Intuitive form for requesting domain changes
- ✅ **Tier-Conditional UI** - Interface adapts based on business subscription tier
- ✅ **Rich Dropdown Components** - Enhanced UX with fancy JavaScript dropdowns

**Custom Domain Workflow:**
1. Business submits domain change request through settings interface
2. System sends email notification to BizBlasts team for review
3. Team reviews request and contacts business within 24-48 hours
4. For custom domains: Domain ownership verification assistance provided
5. System adds approved domain to Render.com via API
6. Email sent with CNAME setup instructions (`domain.com` → `bizblasts.onrender.com`)
7. DNS monitoring checks every 5 minutes for 1 hour
8. Domain automatically activated when CNAME verified
9. SSL certificate provisioned by Render.com

**Environment Variables Required:**
```bash
RENDER_API_KEY=your_render_api_key_here
RENDER_SERVICE_ID=your_render_service_id_here
SUPPORT_EMAIL=bizblaststeam@gmail.com
```

### **Domain Change Request Features**

**🎨 Tier-Adaptive Interface:**
- **Premium Tier**: Full access to custom domain and subdomain options
- **Free/Standard Tier**: Subdomain-only interface with upgrade prompts
- **Smart Labels**: Contextual field labels based on subscription tier
- **Conditional Content**: Premium-specific process steps and domain availability tools

**✨ Enhanced UX Components:**
- **Rich JavaScript Dropdowns**: Replaced HTML selects with interactive dropdowns
- **Hover Effects**: Proper color transitions for buttons and links
- **Consistent Spacing**: Uniform `mb-8` spacing between all form sections
- **Visual Feedback**: Loading states, validation, and success/error messaging

**🔧 Technical Implementation:**
- **Route Integration**: `/manage/settings/business/edit` with domain change form
- **Email Notifications**: Automatic team notifications via `DomainMailer`
- **Turbo Compatible**: Works seamlessly with Rails 8 Hotwire stack
- **Form Validation**: Real-time validation with proper error handling

---

## Prerequisites

* Ruby 3.4.2
* PostgreSQL
* Node.js and Yarn/Bun
* Rails 8.0.2

## Domain Architecture: Subdomain vs Custom Domain

BizBlasts supports two tenant hosting modes with unified routing:

| Host Type            | Database Columns Used | Example |
|----------------------|-----------------------|---------|
| `subdomain` (default)| `subdomain` contains the subdomain **only** (e.g. `acme`) <br/> `hostname` may also be populated but is ignored for routing | `https://acme.bizblasts.com` (production) <br/> `http://acme.lvh.me:3000` (development) |
| `custom_domain`      | `hostname` stores the full custom domain (e.g. `acme-corp.com`) | `https://acme-corp.com` |

### **Unified Tenant Routing System**

**🎯 Key Achievement:** All tenant routes automatically work on both subdomains AND custom domains without code duplication.

#### **Route Architecture:**
```ruby
# config/routes.rb - Single constraint handles both domain types
constraints TenantPublicConstraint do
  scope module: 'public' do
    get '/', to: 'pages#show'           # Works on both testbiz.bizblasts.com AND customdomain.com
    get '/services', to: 'pages#show'   # Works on both domain types
    get '/book', to: 'booking#new'      # Works on both domain types
    # ... all tenant routes work universally
  end
  
  # Cart, orders, payments - all work on both domain types
  resource :cart, controller: 'public/carts'
  resources :orders, controller: 'public/orders'
  resources :payments, controller: 'public/payments'
end
```

#### **Constraint Logic:**
- **`TenantPublicConstraint`**: Matches both `*.bizblasts.com` subdomains AND active custom domains
- **`CustomDomainConstraint`**: Identifies requests from verified custom domains (`status: 'cname_active'`)
- **`SubdomainConstraint`**: Handles `*.bizblasts.com` subdomains (used for admin/manage routes)

#### **Tenant Detection Flow:**
1. **Request arrives** → `ApplicationController#set_tenant`
2. **Subdomain check** → `find_business_by_subdomain` 
3. **Custom domain check** → `find_business_by_custom_domain` (matches both apex and www)
4. **Tenant set** → `ActsAsTenant.current_tenant = business`
5. **Route constraint** → `TenantPublicConstraint` matches and serves tenant content

#### **Mailer URL Reliability:**
```ruby
# ✅ CORRECT: Reliable host determination for critical links
@business.mailer_host                    # Always reliable (defaults to subdomain)
@business.mailer_host(prefer_custom_domain: true)  # Uses custom domain only if fully verified

# ❌ WRONG: Could break if custom domain has DNS issues
@business.hostname                       # Might be unreliable for payments/invoices
```

### **Adding New Tenant Routes**

**✅ Future-Proof Pattern:**
```ruby
# All routes added here automatically work on BOTH subdomains and custom domains
constraints TenantPublicConstraint do
  scope module: 'public' do
    get '/new-feature', to: 'new_feature#index'  # ← Works on testbiz.bizblasts.com AND customdomain.com
  end
end
```

**🚨 Common Mistake:**
```ruby
# ❌ WRONG: Only works on main platform domain
get '/new-feature', to: 'public/new_feature#index'
```

### **Route Validation Tools**

**Automated validation ensures all routes work correctly:**
```bash
# Comprehensive route validation
bin/rails tenant:validate_routes

# Quick development testing
bin/test-tenant-routes

# Test specific new route
bin/test-tenant-routes --route /new-feature
```

**📖 Complete Documentation:** [docs/TENANT_ROUTING_GUIDE.md](docs/TENANT_ROUTING_GUIDE.md)

When generating links or redirects **always use the `TenantHost` helper (it automatically adds `:port` in dev/test)**:

```
if business.host_type_subdomain?
  # Use the subdomain column
  "#{business.subdomain}.#{request.domain}"
else # host_type_custom_domain?
  # Use the hostname column
  business.hostname
end
```

This convention is enforced throughout the codebase (controllers, helpers, mailers, etc.) to ensure users remain on the correct host.

---

## Getting Started

1. Clone the repository
```bash
git clone https://github.com/brianlane/bizblasts.git
cd bizblasts
```

2. Install dependencies
```bash
bundle install
yarn install
# OR if using Bun (recommended for production)
bun install
```

3. Set up the database
```bash
# Create and migrate the database
rails db:create
rails db:migrate

# Seed the database with initial data (including default business/tenant)
rails db:seed
```

4. Start the server
```bash
rails server
```

5. Visit the application at:
   * Main site: http://lvh.me:3000
   * Tenant debug: http://lvh.me:3000/home/debug
   * Specific tenant: http://example.lvh.me:3000 (replace 'example' with your tenant subdomain)

---

## 🚀 **Enhanced Hotwire Architecture**

### **Modern JavaScript Stack**
- **Rails 8.0.2** with latest Hotwire integration
- **Stimulus 3.2.2** with hybrid auto-discovery + manual registration
- **Turbo 8.0.5** with intelligent tenant-aware navigation
- **Custom TurboTenantHelpers** for multi-tenant subdomain management
- **Build System Compatible** - Works with Bun/Yarn without ES module issues

### **Key Hotwire Features**

#### **1. Hybrid Controller Registration**
```javascript
// Manual registration for critical controllers (guaranteed loading)
application.register("page-editor", PageEditorController)
application.register("dropdown", DropdownController)

// Auto-discovery for additional controllers (compatible approach)
const controllersToDiscover = [
  { name: 'hello', path: './controllers/hello_controller' }
  // Add more controllers here as needed
];
```

**✅ Compatibility Note:** The auto-discovery system uses dynamic imports instead of `import.meta.glob()` to ensure compatibility with the current build system and avoid "Cannot use 'import.meta' outside a module" errors. Critical controllers like the test `hello` controller are manually registered for maximum reliability.

#### **2. Tenant-Aware Turbo Navigation**
```javascript
// Smart navigation: Fast Turbo within tenant, safe full loads between tenants
document.addEventListener("turbo:before-visit", (event) => {
  if (TurboTenantHelpers.isCrossTenantNavigation(event.detail.url)) {
    event.preventDefault();
    window.location.href = event.detail.url; // Full page load for security
  }
});
```

#### **3. Automatic Form Enhancement**
```erb
<!-- Forms automatically get tenant context -->
<%= form_with model: @booking do |f| %>
  <!-- Your form fields -->
<% end %>

<!-- Results in hidden fields being added:
<input type="hidden" name="tenant_context" value="business-manager">
<input type="hidden" name="current_tenant" value="acme-corp">
-->
```

#### **4. Development Debugging**
```javascript
// Available in browser console during development
TenantHelpers.debugTenantInfo()
// Auto-logged on page load with tenant information
```

### **Creating New Stimulus Controllers**

**Option 1: Auto-Discovery (Recommended)**
```bash
# Create the file - it will be auto-discovered
touch app/javascript/controllers/my_feature_controller.js
```

**Option 2: Manual Registration (For critical controllers)**
```javascript
// Add to application.js
import MyFeatureController from "./controllers/my_feature_controller"
application.register("my-feature", MyFeatureController)
```

### **TurboTenantHelpers Utilities**
```javascript
// Environment detection
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

---

## 🧪 **Comprehensive Testing Suite**

### **Test Coverage: 61 Tests Total**
- **23 System Tests** - Full browser integration testing
- **38 JavaScript Unit Tests** - Jest-powered unit testing
- **100% Hotwire Coverage** - All auto-discovery and tenant utilities tested

### **Running Tests**

**All Tests:**
```bash
bin/test
```

**Hotwire-Specific Tests:**
```bash
bin/test-hotwire
```

**JavaScript Unit Tests Only:**
```bash
npm test
# OR
bun test
```

**RSpec Only:**
```bash
bundle exec rspec
```

### **Test Structure**
```
spec/
├── system/
│   ├── hotwire_setup_spec.rb           # Comprehensive Hotwire integration
│   ├── stimulus_auto_discovery_spec.rb  # Auto-discovery functionality
│   └── ...
├── javascript/
│   ├── turbo_tenant_helpers_spec.js    # TurboTenantHelpers unit tests
│   └── setup.js                       # Jest configuration
└── ...
```

### **Key Test Features**
- **Cuprite Integration** - Headless Chrome testing optimized for Rails
- **JavaScript Execution Testing** - Validates Stimulus controller loading
- **Tenant Context Testing** - Multi-tenant navigation and form enhancement
- **Production Environment Testing** - Ensures production compatibility
- **Auto-Discovery Validation** - Confirms controller registration works

---

## 🔧 **Complete Turbo Compatibility Achievement**

### **Mission Accomplished: 56+ Files Converted**

**All `DOMContentLoaded` event listeners have been successfully converted to Turbo-compatible patterns!**

#### **What Was Fixed:**
```javascript
// OLD PATTERN (Turbo incompatible):
document.addEventListener('DOMContentLoaded', function() {
  // functionality
});

// NEW PATTERN (Turbo compatible):
function initializeFunctionName() {
  // functionality with null checks
}
document.addEventListener('DOMContentLoaded', initializeFunctionName);
document.addEventListener('turbo:load', initializeFunctionName);
```

#### **Categories Completed:**
- ✅ **High Priority (Business Critical):** 8 files - Service forms, booking management, customer management
- ✅ **Medium Priority (User-Facing):** 12 files - Booking forms, payment processing, registration
- ✅ **Lower Priority (Admin & Settings):** 25+ files - Business settings, staff management, integrations
- ✅ **Additional Files Found:** 11+ files - Documentation, JavaScript modules, Active Admin

#### **Critical Systems Now Turbo-Compatible:**
- **Business Management** - Service forms, booking management, customer management, promotions
- **Customer Experience** - Booking forms, payment processing, tip collection, account creation
- **Admin Interface** - User management, settings, availability management, Active Admin enhancements
- **Public Pages** - Registration forms, estimate requests, FAQ functionality, documentation
- **Core Infrastructure** - Navigation, modals, form validation, dynamic pricing
- **JavaScript Modules** - Copy functionality, form helpers, validation systems

#### **Benefits Achieved:**
1. **🔧 Full Turbo Compatibility** - All JavaScript functionality works with Turbo navigation
2. **⚡ Improved Performance** - Faster page transitions with Turbo caching
3. **🛡️ Enhanced Reliability** - Added null checks and error handling
4. **📱 Better User Experience** - Smooth navigation without page reloads
5. **🏗️ Future-Proof Architecture** - Ready for modern SPA-like experience

---

## 🆕 Service Variants

Businesses can now define multiple "variants" of a core service — for example a 30-minute and 60-minute massage — without duplicating the base record.

1. Navigate to **Manage → Services → Edit** and scroll to **Service Variants**.
2. Add rows specifying `Name`, `Duration (min)`, and `Price`. You can toggle whether each variant is **Active**.
3. At checkout the customer selects the desired variant; all pricing, duration, and Stripe line-items automatically adjust.

All existing services have been migrated to a single default variant so your data remains intact.

---

## 🏗️ **Multi-Tenancy Implementation**

This application uses the `acts_as_tenant` gem for multi-tenancy with enhanced Hotwire support:

1. **Tenants identified by subdomain** with intelligent Turbo navigation
2. **Tenant data scoped** with the `business_id` column on models
3. **All models** requiring tenant isolation use `acts_as_tenant(:business)`
4. **Application controller** sets current tenant based on subdomain
5. **TurboTenantHelpers** provides utilities for cross-tenant navigation

### Adding a New Tenant-Scoped Model

```ruby
class YourModel < ApplicationRecord
  acts_as_tenant(:business)
  # rest of your model...
end
```

---

## 🎨 **Styling with Tailwind CSS**

This application uses the `tailwindcss-rails` gem with ActiveAdmin support.

### Development Workflow

```bash
bin/dev
```

This runs:
- `web`: `bin/rails server`
- `css`: `bin/rails tailwindcss:watch`

### Brand & Functional Colors

Core Brand Colors:
- `primary` (#1A5F7A)
- `secondary` (#57C5B6)
- `accent` (#FF8C42)
- `dark` (#333333)
- `light` (#F8F9FA)

Functional Colors:
- `success` (#28A745)
- `warning` (#FFC107)
- `error` (#DC3545)
- `info` (#17A2B8)

---

## 🚀 **Production Deployment (Render.com)**

### **Enhanced Build Process**
The `bin/render-build.sh` script now includes:

1. **Bun Installation** - Fast JavaScript package management
2. **Production Dependencies** - Optimized for performance
3. **JavaScript Bundling** - Hotwire assets properly compiled
4. **CSS Compilation** - Both Tailwind and ActiveAdmin

### **Production Features**
- **Environment Detection** - Automatic production vs development mode
- **Debug Mode Disabled** - No console logging in production
- **Optimized Bundle Size** - Jest and dev dependencies excluded
- **Tenant URL Generation** - Works with bizblasts.com domain

### **Deployment Verification**
```bash
# Test production build locally
RAILS_ENV=production bundle exec rails assets:precompile
```

---

## 📚 **Documentation**

### **Hotwire Documentation**
- **[docs/HOTWIRE_SETUP.md](docs/HOTWIRE_SETUP.md)** - Complete Hotwire setup guide
- **[docs/PRODUCTION_COMPATIBILITY.md](docs/PRODUCTION_COMPATIBILITY.md)** - Production deployment guide

### **Development Guides**
- **[docs/TAILWIND_CI_FIX.md](docs/TAILWIND_CI_FIX.md)** - Tailwind CI configuration
- **[todo-list-dom.md](todo-list-dom.md)** - Complete DOMContentLoaded conversion log

---

## 🧪 **Testing Best Practices**

### **Writing Tests**
- **Model tests:** `spec/models/`
- **Request tests:** `spec/requests/`
- **System tests:** `spec/system/`
- **JavaScript tests:** `spec/javascript/`
- **Mailer tests:** `spec/mailers/`
- **Job tests:** `spec/jobs/`

### **Factories**
```ruby
# Create a record and save it to the database
user = create(:user)

# Build a record without saving it
business = build(:business, name: "Custom Name")
```

### **Hotwire Testing Patterns**
```ruby
# Test Stimulus controller loading
expect(page).to have_css('[data-controller="hello"]')

# Test auto-discovery
expect(page.evaluate_script('window.Stimulus.router.modules')).to include('hello')

# Test tenant utilities
expect(page.evaluate_script('TurboTenantHelpers.getCurrentTenant()')).to eq('test-business')
```

---

## 🔄 **Continuous Integration**

Tests automatically run on GitHub Actions:
1. When pull requests are created or updated
2. When code is pushed to the main branch
3. Includes both RSpec and Jest test suites
4. Validates Hotwire functionality and production compatibility

---

## 📈 **Performance Features**

### **Hotwire Optimizations**
1. **Auto-Discovery** - Only loads controllers that exist
2. **Tenant-Aware Caching** - Prevents cross-tenant data leaks
3. **Smart Navigation** - Fast Turbo within tenant, safe full loads between tenants
4. **Development Debugging** - Easy troubleshooting with detailed logging

### **Production Optimizations**
- **Minimal Bundle Size** - Development dependencies excluded
- **Fast JavaScript Runtime** - Bun for package management
- **Optimized Asset Pipeline** - Proper compression and caching
- **Environment-Specific Features** - Debug mode only in development

---

## 🚀 **Core Features**

* **Multi-tenant architecture** using acts_as_tenant with Hotwire support
* **Modern Authentication** using Devise with Turbo compatibility
* **Customizable business templates** with live preview
* **Payment processing** with Stripe integration
* **Advanced booking system** with real-time availability
* **Comprehensive admin interface** with ActiveAdmin
* **Mobile-responsive design** with Tailwind CSS
* **Full-text search** capabilities
* **Email automation** with multiple mailer systems
* **File upload and management** with Active Storage
* **Background job processing** with Solid Queue

---

## 🎯 **Development Philosophy**

### **Slogan**
*Simpler is Better*

### **Tagline**
*Starting a Business? Biz blast your business with booking scheduling, payment processing, and its own website all for free*

### **Technical Principles**
1. **Modern Rails Patterns** - Rails 8 best practices with Hotwire
2. **Comprehensive Testing** - Every feature thoroughly tested
3. **Production Ready** - Optimized for real-world deployment
4. **Developer Experience** - Rich debugging and documentation
5. **Performance First** - Fast loading and smooth interactions
6. **Multi-Tenant Security** - Proper data isolation and navigation

---

## 🔮 **Future Enhancements**

- **Lazy Loading Controllers** - Load controllers based on DOM presence
- **Enhanced Tenant Error Handling** - Tenant-specific error pages
- **Performance Monitoring** - Cross-tenant navigation analytics
- **Advanced Caching Strategies** - Tenant-specific asset optimization
- **Progressive Web App** - Enhanced mobile experience
- **Real-time Features** - WebSocket integration for live updates

---

## 📝 **Migration Notes**

### **From Previous Versions**
- All existing controllers continue to work with manual registration
- New controllers can use auto-discovery
- All DOMContentLoaded listeners have been converted to Turbo-compatible patterns
- Enhanced multi-tenant navigation with intelligent routing

### **Breaking Changes**
- None! This enhancement maintains full backwards compatibility

---

## 🔒 Security

BizBlasts implements comprehensive security measures to protect multi-tenant data and prevent unauthorized access.

### Security Architecture

#### Multi-Tenant Isolation
- **ActsAsTenant Gem**: Automatic tenant scoping for all business data
- **Tenant Context Management**: Secure tenant switching with business verification
- **Cross-Tenant Protection**: Prevents access to data from other businesses
- **Database Constraints**: Foreign key relationships enforce tenant boundaries

#### API Security
- **Authentication Required**: All sensitive endpoints require API key authentication
- **Rate Limiting**: 100 requests per hour per IP address
- **Data Minimization**: API responses exclude sensitive information (emails, phone numbers, addresses)
- **Tenant-Aware Responses**: API results are properly scoped to authorized businesses

#### Authorization & Access Control
- **Pundit Policies**: Comprehensive authorization rules for all resources
- **Role-Based Access**: Manager, staff, and client roles with appropriate permissions
- **Business Ownership Validation**: All actions verify user belongs to the target business
- **Admin Separation**: Platform administrators use separate AdminUser model

#### Security Monitoring & Logging

##### Audit Logging System
```ruby
# Automatically logs all security events
SecureLogger.security_event('unauthorized_access', {
  user_id: current_user&.id,
  ip: request.remote_ip,
  path: request.fullpath,
  method: request.method
})
```

##### Automated Security Alerts
- **Real-time Monitoring**: Suspicious activity triggers immediate alerts
- **Email Notifications**: Critical security events are emailed to administrators
- **Event Types Monitored**:
  - Unauthorized access attempts
  - Cross-tenant boundary violations
  - Email enumeration attacks
  - Suspicious request patterns
  - Authorization failures

##### Data Sanitization
```ruby
# Automatic removal of sensitive data from logs
SecureLogger.info("User login attempt: user@example.com")
# Logs as: "User login attempt: use***@***"
```

**Sensitive Data Patterns Removed:**
- Email addresses → `use***@***`
- Phone numbers → `***-***-1234`
- SSN numbers → `[REDACTED_SSN]`
- Credit card numbers → `[REDACTED_CREDIT_CARD]`
- API keys → `[REDACTED_API_KEY]`

### Security Features

#### Email Enumeration Protection
- **Consistent Responses**: Same response for existing and non-existing emails
- **Rate Limiting**: Prevents automated email discovery attempts
- **Security Logging**: Failed enumeration attempts are logged and monitored

#### Input Validation & Sanitization
- **XSS Prevention**: All user input is sanitized before display
- **SQL Injection Protection**: Parameterized queries and ORM usage
- **Path Traversal Prevention**: File access controls and validation
- **Command Injection Protection**: Input sanitization for system commands

#### Session & Authentication Security
- **CSRF Protection**: Rails authenticity tokens for all forms
- **Secure Sessions**: HTTPOnly and secure cookie flags
- **Magic Link Authentication**: Secure passwordless login option
- **Session Timeout**: Automatic logout after inactivity

### Security Testing

#### Automated Security Tests
```bash
# Run security-specific test suite
rspec spec/security/

# Test categories:
# - API Security (authentication, rate limiting, data exposure)
# - Tenant Isolation (cross-tenant access prevention)
# - Policy Security (authorization rules)
# - Secure Logging (data sanitization)
```

#### Security Test Coverage
- **API Authentication**: Verifies all endpoints require proper authentication
- **Tenant Boundary Testing**: Ensures users cannot access other businesses' data
- **Policy Enforcement**: Tests all Pundit policies for proper authorization
- **Data Sanitization**: Verifies sensitive data is removed from logs
- **Email Enumeration**: Confirms protection against user discovery attacks

### Security Configuration

#### Environment Variables
```bash
# Required security configuration
ADMIN_EMAIL=admin@yourcompany.com  # Security alert recipient
API_KEY=your_secure_api_key_here   # API authentication key
SECRET_KEY_BASE=your_rails_secret  # Rails session encryption
```

#### Production Security Checklist
- [ ] Set strong API keys in environment variables
- [ ] Configure ADMIN_EMAIL for security alerts
- [ ] Enable SSL/TLS encryption (HTTPS)
- [ ] Set up log monitoring and retention
- [ ] Configure rate limiting rules
- [ ] Review and test tenant isolation
- [ ] Verify backup encryption and access controls

### Security Incident Response

#### Monitoring Dashboard
Security events are automatically logged and can be monitored through:
- Application logs (`Rails.logger`)
- Security event logs (`SecureLogger`)
- Email alerts for critical events
- Database audit trail for sensitive actions

#### Incident Types & Responses
- **Unauthorized Access**: Automatic user session termination and alert
- **Cross-Tenant Violation**: Immediate access blocking and investigation
- **Enumeration Attack**: IP rate limiting and monitoring escalation
- **Data Breach Attempt**: Full security audit and incident response activation

### Security Maintenance

#### Regular Security Tasks
- **Weekly**: Review security logs for anomalies
- **Monthly**: Update dependencies and security patches
- **Quarterly**: Comprehensive security testing and audit
- **Annually**: Third-party security assessment and penetration testing

#### Security Updates
Security fixes are prioritized and deployed immediately. Monitor:
- Rails security announcements
- Dependency vulnerability alerts (Dependabot)
- Security audit logs for emerging threats
- Industry security best practices

---

**Last Updated:** January 2025  
**BizBlasts Technical Team**  
**Status:** ✅ Production Ready with Enhanced Security & Hotwire Integration