require 'simplecov'

# Configure simplecov for test coverage reporting
SimpleCov.start 'rails' do
  # Set a command name to ensure results merge correctly in parallel tests
  command_name "RSpec-#{ENV['TEST_ENV_NUMBER'] || 'main'}"

  add_filter '/bin/'
  add_filter '/db/'
  add_filter '/spec/' # Don't include tests in coverage
  add_filter '/config/'
  add_filter '/vendor/'

  # Enable branch coverage analysis (disabled in CI for performance)
  enable_coverage :branch unless ENV['DISABLE_SIMPLECOV_BRANCH'] || ENV['CI']
  
  # Combine coverage reports from parallel tests
  merge_timeout 3600 # Set a generous timeout for merging (e.g., 1 hour)
  
  # Use JSON formatter for parallel compatibility
  if ENV['TEST_ENV_NUMBER']
    SimpleCov.at_exit do
      SimpleCov.result.format!
    end
  end
end

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
require 'stripe' # Added for Stripe API mocking
require 'factory_bot_rails'
require 'shoulda/matchers'
require 'database_cleaner/active_record'
require 'parallel_tests/rspec/runtime_logger' # If using parallel_tests logging
require 'capybara/rails'
require 'fileutils' # Add FileUtils for directory creation
require 'warden'
require 'active_storage_validations/matchers'
require 'support/kaminari'
require 'rails-controller-testing'
require 'timecop'
Rails::Controller::Testing.install
# require 'mock_asset_helpers' # REMOVED: Support files are loaded later by RSpec

# Load all support files
Dir[Rails.root.join('spec/support/**/*.rb')].sort.each { |f| require f }

# Set up the database for testing
begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

# Define DatabaseCleaner constants globally
EXCLUDED_TABLES ||= %w[schema_migrations ar_internal_metadata].freeze

# Add this after other requires but before RSpec.configure
require 'rspec/retry'

# RSpec configuration
RSpec.configure do |config|
  # Include Factory Bot syntax methods
  config.include FactoryBot::Syntax::Methods

  # Include Devise helpers
  config.include Devise::Test::ControllerHelpers, type: :controller
  config.include Devise::Test::IntegrationHelpers, type: :request
  config.include Devise::Test::IntegrationHelpers, type: :feature
  config.include Devise::Test::IntegrationHelpers, type: :system

  # Include Rails URL Helpers explicitly for system and request specs
  config.include Rails.application.routes.url_helpers, type: :system
  config.include Rails.application.routes.url_helpers, type: :request

  # Include custom helpers
  config.include ActiveAdminHelpers, type: :request
  config.include TenantHelpers
  config.include LoginHelpers
  config.include BridgeHelpers, type: :request
  config.include ActiveSupport::Testing::TimeHelpers
  config.include ActiveJob::TestHelper
  
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

  # Add Warden test helpers for Devise tests
  config.include Warden::Test::Helpers
  config.before(:suite) { Warden.test_mode! }
  config.after(:each) { Warden.test_reset! }

  # Include Active Storage Validations matchers
  config.include ActiveStorageValidations::Matchers, type: :model

  # Include rails-controller-testing helpers for assigns and render_template
  config.include Rails::Controller::Testing::TestProcess, type: :controller
  config.include Rails::Controller::Testing::TemplateAssertions, type: :controller
  config.include Rails::Controller::Testing::Integration, type: :request

  # == DatabaseCleaner Configuration for Parallel Tests ==
  # Use truncation strategy for all tests to ensure proper isolation
  # Transaction strategy causes issues with request specs (different DB connections)
  
  config.before(:suite) do
    # Ensure DB is clean before suite
    DatabaseCleaner.clean_with(:truncation, except: EXCLUDED_TABLES)
    # Set the default strategy for the suite
    DatabaseCleaner.strategy = :truncation, { except: EXCLUDED_TABLES }
    # Rewind sequences AFTER cleaning so factories start from a clean baseline
    FactoryBot.rewind_sequences if FactoryBot.respond_to?(:rewind_sequences)
  end

  config.around(:each) do |example|
    # Skip cleaning if :seed_test or :no_db_clean metadata is present
    if example.metadata[:seed_test] || example.metadata[:no_db_clean]
      example.run
    else
      # Use truncation for all tests to ensure proper isolation
      DatabaseCleaner.strategy = :truncation, { except: EXCLUDED_TABLES }
      DatabaseCleaner.cleaning do
        example.run
      end
    end
    
    # Reset tenant after each test (important)
    ActsAsTenant.current_tenant = nil
    
    # Rewind sequences after each test
    FactoryBot.rewind_sequences if FactoryBot.respond_to?(:rewind_sequences)
    
    # Reset Capybara session state only for system/feature tests
    if example.metadata[:type] == :system || example.metadata[:type] == :feature
      Capybara.reset_sessions!
    end

    # CRITICAL: Clear ActiveRecord association caches to prevent test pollution
    ActiveRecord::Base.clear_cache! if ActiveRecord::Base.respond_to?(:clear_cache!)
    
    # For Rails < 7.1, use the older method
    if defined?(ActiveRecord::Base.clear_active_connections!)
      ActiveRecord::Base.clear_active_connections!
    end
  end
  
  # == End DatabaseCleaner Configuration ==

  # RSpec Rails configurations
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
  config.fixture_paths = [ Rails.root.join("spec/fixtures") ]
  
  # IMPORTANT: Must be false when using truncation strategy
  config.use_transactional_fixtures = false 

  # RSpec Rails can automatically mix in different behaviours to your tests
  config.order = :random
  Kernel.srand config.seed
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end
  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = "tmp/spec_examples.txt"
  config.disable_monkey_patching!
  config.profile_examples = ENV['PROFILE_SPECS'] ? ENV['PROFILE_SPECS'].to_i : 0

  # Capybara configuration is handled in spec/support/capybara.rb

  # Assign dynamic server ports for parallel tests, or default port for single tests
  if ENV['TEST_ENV_NUMBER']
    Capybara.server_port = 9887 + ENV['TEST_ENV_NUMBER'].to_i
  else
    # For single test runs, use a consistent port to avoid connection issues
    Capybara.server_port = 3000
  end

  Capybara.javascript_driver = :cuprite
  
  config.include Pundit::Authorization, type: :view

  # RSpec Retry Configuration for flaky tests - optimized for CI performance
  config.verbose_retry = true
  config.display_try_failure_messages = true
  
  # Only retry specific browser-related errors and only in CI
  # Reduced retries for faster feedback - 1 retry (2 total attempts)
  config.around(:each, type: :system) do |ex|
    if ENV['CI'] == 'true'
      ex.run_with_retry(
        retry: 1,  # 1 retry only (2 total) - reduced from 2 retries
        exceptions_to_retry: [
          Ferrum::ProcessTimeoutError,
          Ferrum::TimeoutError,
          Net::ReadTimeout
        ],
        retry_callback: -> { Capybara.reset! }
      )
    else
      ex.run
    end
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
