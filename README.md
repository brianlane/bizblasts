# BizBlasts

BizBlasts is a multi-tenant Rails 8 application for small business websites with software leasing capabilities.

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
* Software leasing functionality
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
