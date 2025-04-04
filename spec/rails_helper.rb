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
# Add additional requires below this line. Rails is not loaded until this point!
require 'factory_bot_rails'
require 'shoulda/matchers'
require 'database_cleaner/active_record'
require 'parallel_tests/rspec/runtime_logger' # If using parallel_tests logging
require 'capybara/rails'
require 'simplecov'
require 'fileutils' # Add FileUtils for directory creation
# require 'mock_asset_helpers' # REMOVED: Support files are loaded later by RSpec

# Configure simplecov for test coverage reporting
SimpleCov.start 'rails' do
  add_filter '/bin/'
  add_filter '/db/'
  add_filter '/spec/'
  add_filter '/config/'
  add_filter '/vendor/'
end

# Load all support files
Dir[Rails.root.join('spec/support/**/*.rb')].sort.each { |f| require f }

# Set up the database for testing
begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

# Define DatabaseCleaner constants globally (use ||= to prevent reinitialization)
EXCLUDED_TABLES ||= %w[schema_migrations ar_internal_metadata].freeze
# Revised truncation order - dependent tables first
TRUNCATION_ORDER ||= %w[
  active_storage_variant_records
  active_storage_attachments
  active_storage_blobs
  bookings
  services_staff_members 
  services 
  staff_members 
  tenant_customers 
  users 
  admin_users
  businesses 
].freeze

# RSpec configuration
RSpec.configure do |config|
  # Ensure test schema is up-to-date before any configuration (REMOVED - Handled by parallel_helper.rb)
  # ActiveRecord::Migration.maintain_test_schema!

  # Allow DatabaseCleaner to run even if DATABASE_URL is remote
  DatabaseCleaner.allow_remote_database_url = true 

  # Include Factory Bot syntax methods
  config.include FactoryBot::Syntax::Methods

  # Configure DatabaseCleaner hooks (start/clean handled in database_cleaner.rb)
  # Note: Strategy is set in the database_cleaner.rb before(:each) hook
  # config.before(:suite) do
  #   DatabaseCleaner.strategy = :transaction
  # end

  config.before(:each) do
    DatabaseCleaner.strategy = :transaction
  end

  # Use truncation for system tests or JS tests
  config.before(:each, type: :system) do
    DatabaseCleaner.strategy = :truncation
  end

  config.before(:each, js: true) do
    DatabaseCleaner.strategy = :truncation
  end

  config.before(:each) do
    DatabaseCleaner.start
  end

  # Clean after each test using standard DatabaseCleaner clean (Now re-enabled)
  config.after(:each) do |example|
    if example.metadata[:no_db_clean]
      puts "--- Skipping DB clean for example: #{example.description} ---"
    else
      begin
        # DatabaseCleaner.clean # DISABLED FOR PARALLEL - Causes deadlocks
      rescue ActiveRecord::ConnectionNotEstablished
        puts "--- WARN: Skipping DB clean due to ConnectionNotEstablished in example: #{example.description} ---"
      end
    end
    # Reset tenant after each test
    ActsAsTenant.current_tenant = nil
  end

  # Ensure a final cleanup after the suite (optional, but good practice)
  # config.after(:suite) do
  #   DatabaseCleaner.clean_with(:truncation)
  # end

  # Load seeds once for the entire suite using file lock

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

  # == DatabaseCleaner Configuration ==
  # REMOVED - require 'database_cleaner/active_record' should handle this.
  # DatabaseCleaner.orm = :active_record 

  config.before(:suite) do
    # Allow remote database URL if needed (e.g., CI environment)
    DatabaseCleaner.allow_remote_database_url = true
    # Ensure the database is clean before the suite starts
    DatabaseCleaner.clean_with(:truncation, except: EXCLUDED_TABLES)
    # FactoryBot sequences need rewinding (keep this here)
    FactoryBot.rewind_sequences
  end

  # Clean before running seed context tests using deletion (faster)
  config.before(:context, :seed_context) do
    puts "--- Cleaning DB before seed context using DELETION ---"
    DatabaseCleaner.clean_with(:deletion, except: EXCLUDED_TABLES)
  end

  config.before(:each) do |example|
    # Default to :transaction strategy
    DatabaseCleaner.strategy = :transaction
    # System tests override to use truncation
    if example.metadata[:type] == :system || example.metadata[:js]
       DatabaseCleaner.strategy = :truncation, { except: EXCLUDED_TABLES, pre_count: true, reset_ids: true }
    end
    DatabaseCleaner.start
  end

  # Clean after each test using the determined strategy
  config.after(:each) do |example|
    if example.metadata[:no_db_clean]
      puts "--- Skipping DB clean for example: #{example.description} ---"
    else
      begin
        # DatabaseCleaner.clean # DISABLED FOR PARALLEL - Causes deadlocks
      rescue ActiveRecord::ConnectionNotEstablished
        puts "--- WARN: Skipping DB clean due to ConnectionNotEstablished in example: #{example.description} ---"
      end
    end
  end
  # == End DatabaseCleaner Configuration ==

  # RSpec Rails configurations
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  # Remove this line if you're not using ActiveRecord or ActiveRecord fixtures
  config.fixture_paths = [
    Rails.root.join("spec/fixtures")
  ]

  # If you're not using ActiveRecord, or you'd prefer not to run each of your
  # examples within a transaction, remove the following line or assign false
  # instead of true.
  config.use_transactional_fixtures = true

  # RSpec Rails can automatically mix in different behaviours to your tests
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
