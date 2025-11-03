# Developer Guide

This guide covers the development setup, architecture decisions, and common workflows for working on this Rails 8 application.

## Table of Contents

- [Asset Pipeline Architecture](#asset-pipeline-architecture)
- [Development Setup](#development-setup)
- [Adding New JavaScript](#adding-new-javascript)
- [Adding New Styles](#adding-new-styles)
- [Content Security Policy (CSP)](#content-security-policy-csp)
- [Multi-Tenancy](#multi-tenancy)
- [Testing](#testing)
- [Troubleshooting](#troubleshooting)

---

## Asset Pipeline Architecture

This application uses a **dual asset pipeline** approach:

### Main Application (Modern JS)
- **Bundler**: Bun (fast JavaScript bundler)
- **Entry Point**: `app/javascript/application.js`
- **Output**: `app/assets/builds/application.js`
- **Styles**: Tailwind CSS + Sass
- **Rails UJS**: `@rails/ujs` (modern)

### ActiveAdmin (Legacy Compatibility)
- **Bundler**: Sprockets (Rails asset pipeline)
- **Entry Point**: `app/assets/javascripts/active_admin.js`
- **Output**: Served directly by Sprockets with fingerprinting
- **Styles**: Sass with ActiveAdmin theming
- **Rails UJS**: `jquery_ujs` (jQuery-based)

### Why This Architecture?

**ActiveAdmin 3.3** requires jQuery and is not yet compatible with modern JS bundlers for all features. We use:
- **Sprockets** for ActiveAdmin to maintain full compatibility
- **Bun** for the main application to use modern JavaScript features

This provides:
✅ Full ActiveAdmin functionality
✅ Modern JavaScript for the main app
✅ No conflicts between jQuery and modern JS
✅ Clear separation of concerns

**⚠️ CRITICAL**: Do NOT build `active_admin.js` with Bun/esbuild in CI or production. This causes:
```
Sprockets::DoubleLinkError: Multiple files with the same output path
cannot be linked ("active_admin.js")
```
Sprockets must be the **ONLY** processor for ActiveAdmin JavaScript.

---

## Development Setup

### Prerequisites

```bash
# Ruby version
ruby -v  # Should be 3.4.3+

# Node.js and Bun
node -v  # Should be 20+
bun -v   # Should be 1.0+

# PostgreSQL
psql --version  # Should be 14+
```

### Initial Setup

```bash
# Install dependencies
bundle install
bun install

# Setup database
rails db:create
rails db:migrate
rails db:seed

# Start development server
bin/dev
```

The `bin/dev` command starts:
- Rails server on port 3000
- CSS watchers (Tailwind + Sass)
- JavaScript builders (Bun for app, Sprockets compiles automatically)

### Development URLs

- **Main App**: `http://localhost:3000`
- **ActiveAdmin**: `http://localhost:3000/admin`
- **Multi-Tenant**: `http://[subdomain].lvh.me:3000`

---

## Adding New JavaScript

### For Main Application

**Location**: `app/javascript/`

**Example**: Adding a new Stimulus controller

```bash
# Create new controller
touch app/javascript/controllers/my_feature_controller.js
```

```javascript
// app/javascript/controllers/my_feature_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    console.log("My feature connected!")
  }
}
```

**No build step needed** - Bun watches and rebuilds automatically via `bin/dev`.

### For ActiveAdmin

**Location**: `app/assets/javascripts/active_admin/`

**Example**: Adding a custom ActiveAdmin enhancement

```javascript
// app/assets/javascripts/active_admin/my_enhancement.js
(function() {
  'use strict';

  // Wait for DOM ready
  $(document).ready(function() {
    console.log('My enhancement loaded');

    // Your ActiveAdmin-specific code here
    $('.my-selector').on('click', function() {
      // Handle click
    });
  });
})();
```

Then reference it in the manifest:

```javascript
// app/assets/javascripts/active_admin.js
//= require active_admin/my_enhancement
```

**Build automatically** - Sprockets compiles on page load in development.

### Important: Rails UJS

⚠️ **DO NOT** call `Rails.start()` in ActiveAdmin JavaScript files.

- Main app uses `@rails/ujs` (started in `application.js`)
- ActiveAdmin uses `jquery_ujs` (loaded via Sprockets)
- Starting Rails UJS twice causes double-binding issues (duplicate form submissions, AJAX requests, confirmations)

---

## Adding New Styles

### Tailwind CSS (Main Application)

**Location**: Add utility classes directly in views

```erb
<div class="bg-blue-500 text-white p-4 rounded-lg">
  My styled content
</div>
```

**Custom Components**: `app/assets/stylesheets/components/`

```css
/* app/assets/stylesheets/components/button.css */
@layer components {
  .btn-primary {
    @apply bg-blue-500 text-white px-4 py-2 rounded hover:bg-blue-600;
  }
}
```

### Sass (ActiveAdmin)

**Location**: `app/assets/stylesheets/active_admin.scss`

```scss
// Override ActiveAdmin variables
$primary-color: #5E6469;
$secondary-color: #f0f0f0;

// Import ActiveAdmin
@import "active_admin/mixins";
@import "active_admin/base";

// Custom styles
.admin-custom-widget {
  background: $primary-color;
  padding: 1rem;
}
```

---

## Content Security Policy (CSP)

### Configuration

CSP is configured in `config/initializers/content_security_policy.rb`.

**Current Mode**: Report-only (test/development)
```ruby
config.content_security_policy_report_only = true
```

**Production Mode** (future):
```ruby
config.content_security_policy_report_only = false
```

### Nonce-Based Script Protection

All inline scripts should use nonces:

```erb
<%# In views %>
<script nonce="<%= content_security_policy_nonce %>">
  console.log('Safe inline script');
</script>
```

### Allowed Directives

- `script-src`: `'self'`, `https:`, nonces, Termly
- `style-src`: `'self'`, `'unsafe-inline'`
- `img-src`: `'self'`, `https:`, `data:`, `blob:`
- `connect-src`: `'self'`, `https:`, `wss:`, `ws:`

### Testing CSP

```bash
# Run CSP request specs
bundle exec rspec spec/requests/content_security_policy_spec.rb
```

### Troubleshooting CSP

**Issue**: "Refused to execute inline script because it violates CSP"

**Solution**: Add nonce to the script tag:
```erb
<script nonce="<%= content_security_policy_nonce %>">
  // Your code
</script>
```

**Issue**: Third-party scripts blocked

**Solution**: Add domain to whitelist in `content_security_policy.rb`:
```ruby
policy.script_src :self, :https, "https://trusted-domain.com"
```

---

## Multi-Tenancy

### Tenant Scoping

This app uses `acts_as_tenant` with the `Business` model as the tenant.

**Scoping Models**:
```ruby
class MyModel < ApplicationRecord
  acts_as_tenant(:business)
end
```

**Current Tenant**:
```ruby
# In controllers (set automatically)
ActsAsTenant.current_tenant  # => #<Business id: 1, ...>

# In background jobs
ActsAsTenant.with_tenant(business) do
  # Tenant-scoped operations
end
```

### Subdomain Routing

**Development**: Uses `lvh.me` for local multi-tenancy
```
http://acme.lvh.me:3000  # Acme Corp tenant
http://widgets.lvh.me:3000  # Widgets Inc tenant
```

**Production**: Uses actual subdomains or custom domains
```
https://acme.bizblasts.com  # Subdomain
https://acme.com  # Custom domain
```

### Testing Multi-Tenancy

```ruby
# In request specs
RSpec.describe "My Feature", type: :request do
  let(:business) { create(:business) }

  before do
    host! "#{business.hostname}.lvh.me"
    ActsAsTenant.current_tenant = business
  end

  after do
    ActsAsTenant.current_tenant = nil
  end

  it "works with tenant context" do
    get some_path
    expect(response).to be_successful
  end
end
```

---

## Testing

### Running Tests

```bash
# All tests with parallel execution
./bin/test

# Fast mode (no coverage)
./bin/test fast

# Specific test types
bundle exec rspec spec/models
bundle exec rspec spec/requests
bundle exec rspec spec/system

# JavaScript tests
bun test
bun test --watch
```

### Test Organization

```
spec/
├── models/           # Model unit tests
├── requests/         # Controller integration tests
├── system/           # End-to-end browser tests (Cuprite)
├── services/         # Service object tests
├── jobs/             # Background job tests
├── mailers/          # Email tests
├── helpers/          # View helper tests
└── javascript/       # Jest tests for JavaScript
```

### System Tests (Browser)

Uses **Cuprite** (headless Chrome):

```ruby
RSpec.describe "My Feature", type: :system, js: true do
  before do
    driven_by(:cuprite)
  end

  it "works in the browser" do
    visit root_path
    expect(page).to have_content("Welcome")
  end
end
```

### JavaScript Tests (Jest)

```javascript
// spec/javascript/my_feature_spec.js
describe('MyFeature', () => {
  it('does something', () => {
    expect(true).toBe(true);
  });
});
```

---

## Troubleshooting

### Asset Issues

**Problem**: JavaScript changes not appearing

**Solution**:
```bash
# Check if bin/dev is running
ps aux | grep "bin/dev"

# Restart bin/dev
# Press Ctrl+C, then restart:
bin/dev

# Clear asset cache
rm -rf app/assets/builds/*
rm -rf public/assets/*
```

**Problem**: "Bun command not found"

**Solution**:
```bash
# Install Bun
curl -fsSL https://bun.sh/install | bash

# Or via npm
npm install -g bun
```

### Database Issues

**Problem**: "PG::ConnectionBad"

**Solution**:
```bash
# Start PostgreSQL
brew services start postgresql@14

# Or via pg_ctl
pg_ctl -D /usr/local/var/postgresql@14 start

# Verify connection
psql -U postgres -l
```

**Problem**: Migration errors

**Solution**:
```bash
# Reset test database
RAILS_ENV=test rails db:drop db:create db:migrate

# Reset development database (⚠️ destroys data)
rails db:reset
```

### Multi-Tenancy Issues

**Problem**: "ActsAsTenant::Errors::NoTenantSet"

**Solution**: Ensure tenant is set before accessing tenant-scoped models:
```ruby
ActsAsTenant.with_tenant(business) do
  # Your code here
end
```

**Problem**: Wrong tenant data showing

**Solution**: Check subdomain/hostname matching:
```ruby
# In console
Business.find_by(hostname: "acme")  # Should match subdomain
```

### Test Failures

**Problem**: "Cuprite::BrowserError: Target closed"

**Solution**: System test timeout or JavaScript error
```bash
# Run with verbose output
bundle exec rspec spec/system/my_spec.rb --format documentation

# Check JavaScript console errors in test output
```

**Problem**: Flaky system tests

**Solution**: Add explicit waits
```ruby
expect(page).to have_content("Expected text", wait: 10)
```

### ESLint Issues

**Problem**: ESLint errors blocking commit

**Solution**:
```bash
# Check errors
bun run lint

# Auto-fix fixable issues
bun run lint:fix

# Run on specific file
bun run lint app/javascript/my_file.js
```

---

## CI/CD

### GitHub Actions Workflow

All tests run in parallel across 7 jobs:
- `test-models`
- `test-requests`
- `test-system`
- `test-services-jobs`
- `test-mailers-helpers`
- `test-controllers`
- `test-integration`

### Asset Building in CI

```yaml
# .github/workflows/ci.yml
- name: Build JavaScript Assets
  run: |
    mkdir -p app/assets/builds
    npx esbuild app/javascript/application.js --bundle --outfile=app/assets/builds/application.js
    # ActiveAdmin JavaScript is compiled via Sprockets; no separate bun/esbuild build step
```

### Running CI Locally

```bash
# Install Act (GitHub Actions locally)
brew install act

# Run CI
act -j test-models
```

---

## Code Quality

### Linting

```bash
# Ruby
bundle exec rubocop

# JavaScript
bun run lint
bun run lint:fix
```

### Security Scanning

```bash
# Brakeman (Rails security scanner)
bin/brakeman

# Bundle Audit (gem vulnerabilities)
bundle audit
```

---

## Additional Resources

- [README.md](README.md) - Project overview and setup
- [docs/HOTWIRE_SETUP.md](docs/HOTWIRE_SETUP.md) - Hotwire/Turbo documentation
- [docs/TAILWIND_CI_FIX.md](docs/TAILWIND_CI_FIX.md) - Tailwind CI configuration
- [docs/DOMPURIFY_INTEGRATION.md](docs/DOMPURIFY_INTEGRATION.md) - XSS protection
- [docs/MARKDOWN_PREVIEW_CSP.md](docs/MARKDOWN_PREVIEW_CSP.md) - CSP for markdown

---

## Getting Help

1. Check this guide first
2. Check existing documentation in `/docs`
3. Search closed issues on GitHub
4. Ask in team Slack channel
5. Create a new GitHub issue with:
   - Steps to reproduce
   - Expected vs actual behavior
   - Environment details (Ruby/Node/Bun versions)
   - Relevant logs

---

**Last Updated**: 2025-11-02
**Rails Version**: 8.0.2
**ActiveAdmin Version**: 3.3.0
