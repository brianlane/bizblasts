# frozen_string_literal: true

source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.0.2"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# Use postgresql as the database for Active Record
gem "pg", "~> 1.6"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
gem "jbuilder"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[windows jruby]

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cache"
gem "solid_queue"

gem "aws-sdk-s3", require: false

# Authentication
gem "devise"
gem "devise-jwt"
gem "devise-passwordless"

# Email delivery
gem "resend"

# Authorization
gem "pundit"

# SECURITY FIX: Add rate limiting
gem "rack-attack"

# Admin interface
gem "activeadmin"
# gem "sassc-rails" # REMOVED - Conflicts with Propshaft

# ActiveStorage Validations
gem 'active_storage_validations'

# Multitenancy
gem "acts_as_tenant"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
# gem "kamal", require: false # REMOVED

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
gem "image_processing", "~> 1.2"

# Markdown processing with HTML support
gem "redcarpet"
gem "rouge" # For syntax highlighting

# Stripe for payments
gem "stripe", "~> 15.3"

# Use node based css bundling
gem "cssbundling-rails"
gem "tailwindcss-rails"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri mingw x64_mingw ]
  gem "dotenv-rails"
  gem "factory_bot_rails"
  gem "faker"
  gem "rspec-rails"
  gem "capybara"
  gem "cuprite"
  gem "webdrivers"

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false

  # Testing framework
  gem "shoulda-matchers", "~> 6.5"
  gem "database_cleaner" # Main database_cleaner gem
  gem "database_cleaner-active_record" # For cleaning the database between tests
  
  # For test performance metrics
  gem "simplecov", require: false

  # For checking rendered templates in controller/request specs
  gem "rails-controller-testing"
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"
  # Annotate models
  gem "annotate"
end
# For time-of-day calculations in availability logic
gem 'tod'
gem 'simple_calendar'
# For date grouping in analytics
gem 'groupdate'
gem 'parallel_tests', group: [:development, :test]
gem 'ostruct'
gem "kaminari", "~> 1.2"
gem "rspec-retry", "~> 0.6.2", group: :test
gem 'geocoder'
