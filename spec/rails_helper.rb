# frozen_string_literal: true

# This file is copied to spec/ when you run 'rails generate rspec:install'
require 'spec_helper'
ENV['RAILS_ENV'] ||= 'test'

# Set to completely disable the asset pipeline in tests
ENV['RAILS_DISABLE_ASSET_COMPILATION'] = 'true' 
ENV['DISABLE_PROPSHAFT'] = 'true'

# OpenStruct for mock objects
require 'ostruct'

# Override sprockets-rails manifest builder before loading environment
require 'sprockets/railtie'
module Sprockets
  class Railtie < ::Rails::Railtie
    class << self
      def build_manifest(app)
        config = app.config
        # Return a dummy manifest to bypass the propshaft conflict
        OpenStruct.new(
          compile: false,
          clean: true,
          cache_manifest: false,
          assets: [],
          files: []
        )
      end
    end
  end
end

# Override Sprockets Manifest to handle Propshaft cases
require 'sprockets/manifest'
module Sprockets
  class Manifest
    alias_method :original_initialize, :initialize
    
    # Use a more flexible argument pattern that works with any number of arguments
    def initialize(*args)
      env = args[0]
      dir = args[1]
      
      # Handle Propshaft::Assembly by checking if dir responds to :to_s
      if dir.nil? || (dir.respond_to?(:to_s) && dir.to_s.is_a?(String))
        @environment = env
        @directory = dir.nil? ? nil : File.expand_path(dir.to_s)
        @filename = "manifest.json"
      else
        # If dir is something unusual (like Propshaft::Assembly), use empty settings
        @environment = env
        @directory = nil
        @filename = "manifest.json"
      end
    end
  end
end

# Now it's safe to load the environment
require_relative '../config/environment'

# Prevent database truncation if the environment is production
abort("The Rails environment is running in production mode!") if Rails.env.production?
require 'rspec/rails'
# Add additional requires below this line. Rails is not loaded until this point!
require 'database_cleaner/active_record'

# Load only essential support files for faster boot time
support_files = [
  'database_cleaner',
  'factory_bot',
  'request_spec_helper',
  'acts_as_tenant_helper',
  'devise_helpers'
]

support_files.each do |file|
  require Rails.root.join('spec', 'support', "#{file}.rb")
end

# Checks for pending migrations and applies them before tests are run.
# If you are not using ActiveRecord, you can remove these lines.
begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

# Configure Rails env for faster tests
Rails.application.eager_load! if ENV['CI'].present?

RSpec.configure do |config|
  # Remove this line if you're not using ActiveRecord or ActiveRecord fixtures
  # config.fixture_paths = ["#{::Rails.root}/spec/fixtures"]  # Commented out - using FactoryBot instead

  # If you're not using ActiveRecord, or you'd prefer not to run each of your
  # examples within a transaction, remove the following line or assign false
  # instead of true.
  config.use_transactional_fixtures = false
  
  # Allow using any_instance_of and similar mocks
  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
    mocks.allow_message_expectations_on_nil = false
  end

  # You can uncomment this line to turn off ActiveRecord support entirely.
  # config.use_active_record = false

  # RSpec Rails can automatically mix in different behaviours to your tests
  # based on their file location, for example enabling you to call `get` and
  # `post` in specs under `spec/controllers`.
  #
  # You can disable this behaviour by removing the line below, and instead
  # explicitly tag your specs with their type, e.g.:
  #
  #     RSpec.describe UsersController, type: :controller do
  #       # ...
  #     end
  #
  # The different available types are documented in the features, such as in
  # https://rspec.info/features/6-0/rspec-rails
  config.infer_spec_type_from_file_location!

  # Filter lines from Rails gems in backtraces.
  config.filter_rails_from_backtrace!
  # arbitrary gems may also be filtered via:
  config.filter_gems_from_backtrace("devise", "warden", "rack", "railties", "activerecord")
  
  # Include Devise test helpers
  config.include Devise::Test::IntegrationHelpers, type: :request
  config.include Devise::Test::IntegrationHelpers, type: :system
  config.include DeviseHelpers, type: :system
  config.include RequestSpecHelper, type: :request
  
  # Set up parallel testing with faster database setup
  config.before(:suite) do
    Rails.application.load_seed if ENV['LOAD_SEED_ONCE']
  end
end

# Configure shoulda-matchers with faster defaults
Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end

# Speed up ActiveJob in tests
ActiveJob::Base.queue_adapter = :test
