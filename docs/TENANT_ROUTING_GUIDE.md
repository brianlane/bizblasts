# Tenant Routing Guide

This guide ensures that all future routes work correctly for both subdomains and custom domains.

## Current Architecture

### Route Constraints
- **`TenantPublicConstraint`**: Matches both subdomains (`*.bizblasts.com`) and custom domains
- **`SubdomainConstraint`**: Legacy constraint (now only used for admin/manage routes)
- **`CustomDomainConstraint`**: Matches active custom domains only

### Tenant Detection Flow
1. **Request arrives** → `ApplicationController#set_tenant`
2. **Subdomain check** → `find_business_by_subdomain` 
3. **Custom domain check** → `find_business_by_custom_domain`
4. **Tenant set** → `ActsAsTenant.current_tenant = business`

## ✅ CORRECT: Adding Public Tenant Routes

All public-facing tenant routes MUST be added inside the `TenantPublicConstraint` block:

```ruby
# config/routes.rb
constraints TenantPublicConstraint do
  scope module: 'public' do
    # ✅ CORRECT: Routes for pages, services, booking, etc.
    get '/new-feature', to: 'new_feature#index'
    resources :new_resources, only: [:index, :show]
  end
  
  # ✅ CORRECT: Routes that need to be outside scope module
  resources :special_resources, controller: 'public/special_resources'
end
```

## ❌ WRONG: Common Mistakes

### 1. Adding routes outside tenant constraints
```ruby
# ❌ WRONG: This only works on main domain
get '/new-feature', to: 'public/new_feature#index'
```

### 2. Using tenant-specific route helpers
```ruby
# ❌ WRONG: Creates tenant-specific helpers that break existing code
resources :payments, as: :tenant_payments
```

### 3. Forgetting controller specification
```ruby
# ❌ WRONG: Routes to wrong controller
resources :new_resources  # Routes to NewResourcesController instead of Public::NewResourcesController
```

## Route Helper Naming Rules

### ✅ Use Generic Helper Names
```ruby
# ✅ CORRECT: Generates standard Rails helpers
resources :payments        # → payments_path, new_payment_path
resource :cart            # → cart_path
resources :orders         # → orders_path, new_order_path
```

### ❌ Avoid Custom Helper Names
```ruby
# ❌ WRONG: Creates non-standard helpers that break existing code
resources :payments, as: :tenant_payments  # → tenant_payments_path (breaks existing views)
```

## Controller Patterns

### ✅ Public Controllers
All tenant-facing controllers should be in the `Public` module:

```ruby
# app/controllers/public/new_feature_controller.rb
module Public
  class NewFeatureController < ApplicationController
    # Inherits tenant detection from ApplicationController
  end
end
```

### ✅ Mailer URL Generation
Use the reliable `mailer_host` method for critical links:

```ruby
# ✅ CORRECT: Reliable host determination
<%= link_to 'Pay Now', new_payment_url(invoice_id: @invoice.id, host: @business.mailer_host) %>

# ❌ WRONG: Could break if custom domain has issues
<%= link_to 'Pay Now', new_payment_url(invoice_id: @invoice.id, host: @business.hostname) %>
```

## Testing Requirements

### Controller Tests
```ruby
RSpec.describe Public::NewFeatureController, type: :controller do
  let!(:business) { create(:business, subdomain: 'testtenant') }
  
  before do
    ActsAsTenant.current_tenant = business
    @request.host = 'testtenant.lvh.me'  # ✅ CORRECT: Subdomain host
  end
end
```

### System Tests
```ruby
# ✅ Test both subdomain and custom domain scenarios
context 'on subdomain' do
  before { host! 'testtenant.lvh.me' }
  # ... test scenarios
end

context 'on custom domain' do
  let!(:business) { create(:business, :with_custom_domain) }
  before { host! business.hostname }
  # ... test scenarios  
end
```

## Validation Checklist

Before adding new tenant routes, verify:

- [ ] Route is inside `TenantPublicConstraint` block
- [ ] Controller is in `Public` module
- [ ] Uses generic route helper names (no `as:` unless necessary)
- [ ] Specifies correct controller path if outside scope module
- [ ] Tests work with subdomain host setup
- [ ] Mailer URLs use `@business.mailer_host` for reliability

## Quick Reference

### Current Tenant Route Structure
```ruby
constraints TenantPublicConstraint do
  scope module: 'public' do
    # Pages, services, booking, calendar, products, etc.
  end
  
  # Cart, orders, payments, subscriptions, tips, etc.
  # (outside scope module but with explicit controller paths)
end
```

### Development Testing
```bash
# Test subdomain routing
curl -H "Host: testtenant.lvh.me" http://localhost:3000/new-route

# Test custom domain routing (after setting up test domain)
curl -H "Host: testdomain.com" http://localhost:3000/new-route
```

## Emergency Recovery

If a route breaks tenant functionality:

1. **Check constraint placement** - Ensure route is inside `TenantPublicConstraint`
2. **Verify controller path** - Ensure it points to `Public::` namespace
3. **Test helper names** - Run `bin/rails routes | grep route_name` to verify
4. **Check for duplicates** - Ensure no duplicate route definitions
5. **Validate constraints** - Test that `TenantPublicConstraint.matches?(request)` returns true

This architecture ensures that ALL tenant routes automatically work for both subdomains and custom domains without additional configuration.

## Automated Validation Tools

### 1. Route Validation Rake Task
```bash
# Comprehensive validation of all tenant routes
bin/rails tenant:validate_routes

# Show current route structure
bin/rails tenant:show_routes
```

### 2. Quick Development Testing
```bash
# Test all routes on both domain types
bin/test-tenant-routes

# Test specific route
bin/test-tenant-routes --route /new-feature

# Test specific subdomain
bin/test-tenant-routes --subdomain mybiz
```

### 3. CI/CD Integration
Add to your CI pipeline to catch routing regressions:

```yaml
# .github/workflows/test.yml
- name: Validate Tenant Routes
  run: bin/rails tenant:validate_routes
```

## Future Route Development Workflow

### ✅ Recommended Workflow
1. **Add route** inside `TenantPublicConstraint` block
2. **Run validation**: `bin/rails tenant:validate_routes`
3. **Test locally**: `bin/test-tenant-routes --route /your-new-route`
4. **Write tests** using subdomain host setup
5. **Deploy** with confidence

### 🚨 Red Flags to Watch For
- Routes added outside tenant constraints
- New `as: :tenant_*` route helpers appearing
- Tests failing on both subdomains and custom domains
- Validation tools reporting route issues

This systematic approach ensures that **all future routes will automatically work for both subdomains and custom domains**, preventing the routing issues we previously encountered.

## Navigation Best Practices

### ✅ BizBlasts Logo Navigation
The BizBlasts logo should always link to the main platform (`bizblasts.com`):

```erb
<!-- ✅ CORRECT: Works for both subdomains and custom domains -->
<% if ActsAsTenant.current_tenant %>
  <!-- BizBlasts Logo - links to main domain -->
  <%= link_to main_domain_url_for('/'), class: "logo-link" do %>
    <%= image_tag "bizblasts-logo.svg", alt: "BizBlasts" %>
  <% end %>
  <!-- Tenant Name - links to tenant home -->
  <%= link_to tenant_root_path do %>
    <%= ActsAsTenant.current_tenant.name %>
  <% end %>
<% else %>
  <!-- Platform logo -->
  <%= link_to root_path do %>
    BizBlasts
  <% end %>
<% end %>
```

### ❌ Common Navigation Mistakes
```erb
<!-- ❌ WRONG: Only works for subdomains, breaks on custom domains -->
<% if request.subdomain.present? && request.subdomain != 'www' %>
  <!-- This condition fails on custom domains where subdomain is empty -->
<% end %>

<!-- ❌ WRONG: Logo links back to tenant instead of main platform -->
<%= link_to tenant_root_path do %>
  <%= image_tag "bizblasts-logo.svg" %>  <!-- Should go to bizblasts.com -->
<% end %>
```

### Navigation Principles
1. **BizBlasts logo** → Always links to main platform (`bizblasts.com`)
2. **Tenant name/logo** → Links to tenant homepage (current domain)
3. **Platform links** → Use `main_domain_url_for()` for cross-tenant navigation
4. **Tenant links** → Use standard route helpers (work within current domain)

This ensures consistent branding and navigation across all domain types.
