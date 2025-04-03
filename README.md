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

# Seed the database with initial data (including default company/tenant)
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
2. Tenant data is scoped with the `company_id` column on models
3. All models requiring tenant isolation use `acts_as_tenant(:company)`
4. The application controller sets the current tenant based on subdomain

### Adding a New Tenant-Scoped Model

```ruby
class YourModel < ApplicationRecord
  acts_as_tenant(:company)
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
company = build(:company, name: "Custom Name")
```

### Continuous Integration

Tests are automatically run on GitHub Actions:
1. When pull requests are created or updated
2. When code is pushed to the main branch

The CI workflow is defined in `.github/workflows/ci.yml`.
