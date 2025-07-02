# frozen_string_literal: true

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

  # Configure public file server for tests with Cache-Control for performance.
  config.public_file_server.enabled = true
  config.public_file_server.headers = { "Cache-Control" => "public, max-age=3600" }

  # Show full error reports.
  config.consider_all_requests_local = true
  
  # Use memory store instead of null store for better performance
  config.cache_store = :memory_store, { size: 64.megabytes }

  # Reduce logging in tests
  config.log_level = ENV["DEBUG"] ? :debug : :warn
  config.logger = ActiveSupport::Logger.new(Rails.root.join("log", "test.log"))

  # Devise
  config.action_mailer.default_url_options = { host: "localhost", port: 3000 }

  # Render exception templates for rescuable exceptions and raise for other exceptions.
  config.action_dispatch.show_exceptions = :rescuable

  # Disable request forgery protection in test environment.
  config.action_controller.allow_forgery_protection = false

  # Store uploaded files on the local file system in a temporary directory.
  config.active_storage.service = :test

  config.action_mailer.delivery_method = :test
  config.action_mailer.perform_deliveries = true
  config.action_mailer.default_url_options = { host: "example.com" }

  # Print deprecation notices to the stderr.
  config.active_support.deprecation = :stderr

  # Raise error when a before_action's only/except options reference missing actions.
  config.action_controller.raise_on_missing_callback_actions = true
  
  # Performance optimizations for testing
  config.active_record.verbose_query_logs = false
  config.allow_concurrency = false
  
  # Conditionally disable asset handling in test environment
  # Allow asset compilation when explicitly building assets
  if ENV['RAILS_DISABLE_ASSET_COMPILATION'] == 'true'
    config.assets.enabled = false
    config.assets.compile = false
    config.assets.debug = false
    config.assets.digest = false
    config.assets.prefix = '/null-assets'
  else
    # Allow minimal asset handling for builds
    config.assets.enabled = true
    config.assets.compile = false
    config.assets.debug = false
    config.assets.digest = false
  end
  
  # Disable fragment caching for tests
  config.action_controller.perform_caching = false

  config.hosts = [
    "localhost",
    "127.0.0.1",
    "lvh.me",                      # Allow root lvh.me for system tests
    "www.example.com",
    /.*\.lvh\.me/,
    /[a-z0-9\-]+\.example\.com/
  ]

  config.session_store :cookie_store, key: '_bizblasts_session', domain: :all

  # Set default URL options for routing helpers
  routes.default_url_options[:host] = 'lvh.me'
  
  # Set up test environment variables for email
  ENV['MAILER_EMAIL'] ||= 'from@example.com'
  ENV['ADMIN_EMAIL'] ||= 'admin@example.com'

  # -----------------------------------------------------------------
  # Geocoder configuration for tests
  # Prevent external HTTP calls and return deterministic coordinates
  # -----------------------------------------------------------------
  Geocoder.configure(lookup: :test, ip_lookup: :test)

  # Provide stubbed responses for locations we care about in specs
  Geocoder::Lookup::Test.add_stub(
    "Phoenix, AZ",
    [{ 'latitude' => 33.4484, 'longitude' => -112.0740 }]
  )
  Geocoder::Lookup::Test.add_stub(
    "Phoenix Arizona",
    [{ 'latitude' => 33.4484, 'longitude' => -112.0740 }]
  )
  Geocoder::Lookup::Test.add_stub(
    "Phoenix, Arizona",
    [{ 'latitude' => 33.4484, 'longitude' => -112.0740 }]
  )
end
