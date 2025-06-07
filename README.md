# BizBlasts

BizBlasts is a multi-tenant Rails 8 application for business websites.

## Prerequisites

* Ruby 3.4.2
* PostgreSQL
* Node.js and Yarn

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

## Features

* Multi-tenant architecture using acts_as_tenant
* Authentication using Devise
* Customizable business templates
* Payment processing with Stripe

## Multi-Tenancy Implementation

This application uses the `acts_as_tenant` gem for multi-tenancy. Key aspects:

1. Tenants are identified by subdomain
2. Tenant data is scoped with the `business_id` column on models
3. All models requiring tenant isolation use `acts_as_tenant(:business)`
4. The application controller sets the current tenant based on subdomain

### Adding a New Tenant-Scoped Model

```ruby
class YourModel < ApplicationRecord
  acts_as_tenant(:business)
  # rest of your model...
end
```

## Development

For development purposes, use `lvh.me:3000` to test the multi-tenant functionality with subdomains.

## Testing

This application uses RSpec, FactoryBot, and Shoulda Matchers for testing.

### Running Tests

You can run all tests with the included script:

```bash
bin/test
```

Or run RSpec directly:

```bash
bundle exec rspec
```

### Writing Tests

- Model tests: `spec/models/`
- Request tests: `spec/requests/`
- System tests: `spec/system/`
- Mailer tests: `spec/mailers/`
- Job tests: `spec/jobs/`

### Factories

Factory definitions are in `spec/factories/`. Use them in your tests:

```ruby
# Create a record and save it to the database
user = create(:user)

# Build a record without saving it
business = build(:business, name: "Custom Name")
```

### Continuous Integration

Tests are automatically run on GitHub Actions:
1. When pull requests are created or updated
2. When code is pushed to the main branch

The CI workflow is defined in `.github/workflows/ci.yml`.

## Styling with Tailwind CSS

This application uses the `tailwindcss-rails` gem to power its main styles, alongside a separate build for ActiveAdmin.

### Installation and Setup

1. Ensure the gem is in your Gemfile:

```ruby
gem "tailwindcss-rails"
```

2. Install and bootstrap Tailwind:

```bash
bundle exec rails tailwindcss:install
```

This generates:
- `app/assets/tailwind/application.css` – the Tailwind entrypoint
- `tailwind.config.js` – Tailwind configuration file
- Updates to `app/assets/config/manifest.js` and `app/views/layouts/application.html.erb`

### Development Workflow

To start Rails together with live Tailwind* and ActiveAdmin CSS rebuilding:

```bash
bin/dev
```

Or separately via Procfile.dev:

```bash
foreman start -f Procfile.dev
```

This runs:
- `web`: `bin/rails server`
- `css`: `bin/rails tailwindcss:watch`

### Layouts

- **Main application** layout (`app/views/layouts/application.html.erb`) now includes:
  ```erb
  <%= stylesheet_link_tag "tailwind", data: { "turbo-track" => "reload" } %>
  <%= stylesheet_link_tag "application" %> <!-- your custom SASS overrides -->
  ```

- **ActiveAdmin** continues to load `active_admin.css` separately in its own layout.

### Production Builds (Render)

Your `bin/render-build.sh` script is updated to:

1. Install Ruby and JS dependencies
2. Build *ActiveAdmin* CSS via `bin/sass-build-activeadmin.sh`
3. Run `bundle exec rails assets:precompile` which now also runs the Tailwind build

Ensure your `render.yaml` calls `./bin/render-build.sh` as the `buildCommand` so that both CSS bundles are generated and precompiled.

---

*The tailwindcss gem uses `tailwindcss-ruby` under the hood for blazing-fast compilation in development and production.

### Brand & Functional Colors

This project extends Tailwind's default palette with custom brand and functional colors. You can use these in your utilities:

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

Example usage:
```html
<button class="bg-primary text-white py-2 px-4 rounded">
  Primary Button
</button>
<div class="text-error font-bold">Error occurred</div>
<p class="bg-light p-3">Subtle background</p>
```

## Markdown Styling Troubleshooting

**Problem**: `@apply` directives in SCSS files not working  
**Solution**: Use actual CSS properties instead of `@apply` in `app/assets/stylesheets/custom.css`

**Problem**: Markdown content displaying as plain text  
**Solution**: Add styles to `custom.css` (already imported via application layout) rather than separate SCSS files

# Migration deployment Wed May 28 09:06:48 MST 2025
