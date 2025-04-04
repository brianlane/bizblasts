# frozen_string_literal: true

# This file is copied to spec/ when you run 'rails generate rspec:install'
ENV['RAILS_ENV'] ||= 'test'

# Ensure asset compilation is disabled in tests
ENV['RAILS_ASSET_PIPELINE_DISABLED'] = 'true'

# Load Rails environment
require File.expand_path('../config/environment', __dir__)
abort("The Rails environment is running in production mode!") if Rails.env.production?

# RSpec configurations and support
require 'rspec/rails'
require 'capybara/rails'
require 'simplecov'

# Configure simplecov for test coverage reporting
SimpleCov.start 'rails' do
  add_filter '/bin/'
  add_filter '/db/'
  add_filter '/spec/'
  add_filter '/config/'
  add_filter '/vendor/'
end

# Load all support files
Dir[Rails.root.join('spec/support/**/*.rb')].each { |f| require f }

# Set up the database for testing
begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

# RSpec configuration
RSpec.configure do |config|
  # Include Factory Bot syntax methods
  config.include FactoryBot::Syntax::Methods

  # Configure DatabaseCleaner
  config.before(:suite) do
    DatabaseCleaner.clean_with(:truncation)
  end

  config.before(:each) do
    DatabaseCleaner.strategy = :transaction
  end

  config.before(:each, js: true) do
    DatabaseCleaner.strategy = :truncation
  end

  config.before(:each) do
    DatabaseCleaner.start
  end

  config.after(:each) do
    DatabaseCleaner.clean
  end

  # Include Devise helpers
  config.include Devise::Test::ControllerHelpers, type: :controller
  config.include Devise::Test::IntegrationHelpers, type: :request
  config.include Devise::Test::IntegrationHelpers, type: :feature
  config.include Devise::Test::IntegrationHelpers, type: :system

  # Include custom helpers
  config.include ActiveAdminHelpers, type: :request
  config.include TenantHelpers
  config.include LoginHelpers
  
  # Include mock asset helpers
  config.include MockAssetHelpers, type: :request
  config.include MockAssetHelpers, type: :view
  config.include MockAssetHelpers, type: :controller
  config.include MockAssetHelpers, type: :system

  # Include Capybara for feature specs
  config.include Capybara::DSL, type: :feature
  config.include Capybara::RSpecMatchers, type: :feature
  config.include Capybara::DSL, type: :system
  config.include Capybara::RSpecMatchers, type: :system

  # Increase database statement timeout
  config.before(:suite) do
    ActiveRecord::Base.connection.execute("SET statement_timeout = '10s'")
  end

  # RSpec Rails configurations
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  # Add ActsAsTenant reset after each test
  config.after(:each) do
    ActsAsTenant.current_tenant = nil
  end
end

# Configure Shoulda Matchers
Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end

# Set ActiveJob queue adapter for testing
ActiveJob::Base.queue_adapter = :test
