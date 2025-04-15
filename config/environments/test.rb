# frozen_string_literal: true

# The test environment is used exclusively to run your application's
# test suite. You never need to work with it otherwise. Remember that
# your test database is "scratch space" for the test suite and is wiped
# and recreated between test runs. Don't rely on the data there!

require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # While tests run files are not watched, reloading is not necessary.
  config.enable_reloading = false

  # Eager loading loads your entire application. When running a single test locally,
  # this is usually not necessary, and can slow down your test suite. However, it's
  # recommended that you enable it in continuous integration systems to ensure eager
  # loading is working properly before deploying your code.
  config.eager_load = ENV["CI"].present?

  # Configure public file server for tests with cache-control for performance.
  config.public_file_server.enabled = true
  config.public_file_server.headers = { "cache-control" => "public, max-age=3600" }

  # Show full error reports.
  config.consider_all_requests_local = true
  
  # Use memory store instead of null store for better performance
  config.cache_store = :memory_store, { size: 64.megabytes }

  # Enable logging to a file for tests
  # config.logger = ActiveSupport::Logger.new(nil)
  # config.log_level = :fatal
  config.log_level = :debug
  config.logger = ActiveSupport::Logger.new(Rails.root.join("log", "test.log"))

  # Devise
  config.action_mailer.default_url_options = { host: "localhost", port: 3000 }

  # Render exception templates for rescuable exceptions and raise for other exceptions.
  config.action_dispatch.show_exceptions = :rescuable

  # Disable request forgery protection in test environment.
  config.action_controller.allow_forgery_protection = false

  # Store uploaded files on the local file system in a temporary directory.
  config.active_storage.service = :test

  # Tell Action Mailer not to deliver emails to the real world.
  # The :test delivery method accumulates sent emails in the
  # ActionMailer::Base.deliveries array.
  config.action_mailer.delivery_method = :test
  
  # Skip mail delivery altogether for tests
  config.action_mailer.perform_deliveries = false

  # Set host to be used by links generated in mailer templates.
  config.action_mailer.default_url_options = { host: "example.com" }

  # Print deprecation notices to the stderr.
  config.active_support.deprecation = :stderr

  # Raises error for missing translations.
  # config.i18n.raise_on_missing_translations = true

  # Annotate rendered view with file names.
  # config.action_view.annotate_rendered_view_with_filenames = true

  # Raise error when a before_action's only/except options reference missing actions.
  config.action_controller.raise_on_missing_callback_actions = true
  
  # Performance optimizations for testing
  config.active_record.verbose_query_logs = false
  
  # Faster tests without concurrency checks
  config.allow_concurrency = false
  
  # Enable SQL logging for debugging
  # config.active_record.logger = nil
  config.active_record.logger = ActiveSupport::Logger.new($stdout)
  config.active_record.logger.level = Logger::DEBUG
  
  # Completely disable asset handling for tests
  # config.assets.enabled = false
  # config.assets.compile = false
  # config.assets.css_compressor = nil
  # config.assets.js_compressor = nil
  # config.assets.prefix = "/test-assets"
  
  # Disable fragment caching for tests
  config.action_controller.perform_caching = false

  # Specifies the allowed hosts for preventing Host header attacks.
  # Please make sure you understand the security implications of adding hosts here.
  # See https://guides.rubyonrails.org/configuring.html#config-hosts
  config.hosts = [
    "localhost",               # Standard localhost
    "127.0.0.1",             # Standard loopback IP
    "www.example.com",       # Default RSpec/Capybara host
    /.*\.lvh.me/,            # Allow *.lvh.me for local testing (alternative to example.com)
    # Allow any subdomain of example.com for tenant testing
    /[a-z0-9\-]+\.example\.com/
    # Add any specific custom domains used in tests if not covered by regex
    # "std-biz.com",           # Custom domain from specs
    # "premium-biz.com"        # Custom domain from specs
  ]

  # Allow specific hosts for testing tenant contexts (Now covered by regex above)
  # config.hosts += ["alpha.example.com", "beta.example.com"]

  config.session_store :cookie_store, key: '_bizblasts_session', domain: :all
end
