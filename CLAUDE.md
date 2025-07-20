# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

**Test Suite:**
```bash
./bin/test                  # Run full test suite with parallel processing
./bin/test fast            # Run tests without coverage (faster)
./bin/test-hotwire         # Run Hotwire-specific system tests
npm test                   # JavaScript unit tests with Jest
bundle exec rspec          # RSpec tests only
```

**Development Server:**
```bash
bin/dev                    # Start development server with asset watching
rails server               # Rails server only
```

**Asset Management:**
```bash
yarn run build:css        # Build all CSS (application + ActiveAdmin)
yarn run build:js         # Build JavaScript with Bun
bin/rails tailwindcss:watch  # Watch Tailwind CSS changes
```

**Database Operations:**
```bash
rails db:create db:migrate db:seed  # Setup database
rails db:prepare                    # Prepare test database
```

**Code Quality:**
```bash
bin/brakeman              # Security analysis
bin/rubocop               # Ruby style checking
```

## High-Level Architecture

### Multi-Tenant Rails Application
- **Core Technology:** Rails 8.0.2 with PostgreSQL
- **Tenancy:** Uses `acts_as_tenant` gem with `business_id` column
- **Tenant Identification:** Subdomain-based (e.g., `acme.bizblasts.com`) or custom domains
- **Tenant Scoping:** All models requiring isolation use `acts_as_tenant(:business)`

### Enhanced Hotwire Integration
- **Stimulus 3.2.2** with hybrid auto-discovery + manual registration
- **Turbo 8.0.5** with tenant-aware cross-subdomain navigation
- **TurboTenantHelpers** utility provides multi-tenant navigation methods
- **All DOMContentLoaded listeners converted** to Turbo-compatible patterns

### Authentication & Authorization
- **Devise** for user authentication with custom controllers
- **Pundit** for authorization policies
- **Magic Link Authentication** available via `devise-passwordless`
- **Separate AdminUser model** for ActiveAdmin access
- **Multi-role system:** client, manager, staff with business associations

### Asset Pipeline & Styling
- **Propshaft** asset pipeline (not Sprockets)
- **Tailwind CSS** with custom brand colors and functional colors
- **Bun** for JavaScript bundling and package management
- **SASS** for ActiveAdmin styling compilation
- **Custom build scripts** in `bin/` directory

### Business Domain Model
**Core Entities:**
- `Business` - Tenant model with subdomain/custom domain hosting
- `User` - Multi-role users (client/manager/staff) with business associations  
- `Service` - Business services with variants (duration/pricing options)
- `Booking` - Appointment scheduling with staff assignments
- `Order` - E-commerce orders with products and line items
- `Payment` - Stripe integration for payment processing

**Multi-Tenancy Implementation:**
- Tenant context set via `ApplicationController#set_tenant` 
- Supports both subdomain (`business.bizblasts.com`) and custom domains
- Cross-tenant navigation handled securely with full page loads
- Development uses `lvh.me` domains for testing

### Testing Architecture
- **Parallel Test Execution** with intelligent database splitting
- **System Tests** using Cuprite (headless Chrome) for Hotwire testing
- **Jest Unit Tests** for JavaScript/Stimulus controller testing
- **61 total tests** with comprehensive coverage of Hotwire functionality
- **Test splitting categories:** models, requests, system tests, jobs, mailers

### Key Development Patterns

**Stimulus Controller Creation:**
Controllers auto-discovered from `app/javascript/controllers/` or manually registered in `application.js`

**Multi-Tenant Model Creation:**
```ruby
class YourModel < ApplicationRecord
  acts_as_tenant(:business)
  # model implementation
end
```

**Cross-Tenant Navigation:**
Use `TurboTenantHelpers` JavaScript utilities for safe tenant switching that preserves security boundaries.

**Background Jobs:**
Uses `solid_queue` for job processing - start with `bin/jobs`

## Important Files & Directories

- `app/controllers/application_controller.rb` - Core tenant setup and authentication logic
- `app/javascript/application.js` - Hotwire setup with auto-discovery
- `app/javascript/helpers/turbo_tenant_helpers.js` - Multi-tenant utilities  
- `bin/test` - Advanced parallel test runner with optimization
- `docs/HOTWIRE_SETUP.md` - Complete Hotwire implementation guide
- `config/routes.rb` - Multi-tenant routing with subdomain constraints
- `Procfile.dev` - Development server configuration with asset watching

## Deployment & Production

- **Production Platform:** Render.com with `bin/render-build.sh` 
- **Asset Compilation:** Bun handles JavaScript, Tailwind handles CSS
- **Environment Detection:** Production vs development mode automatically detected
- **Database:** PostgreSQL with connection pooling and error handling
- **Security:** Rate limiting via `rack-attack`, CSRF protection, secure tenant isolation