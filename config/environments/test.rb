# frozen_string_literal: true

# The test environment is used exclusively to run your application's
# test suite. You never need to work with it otherwise. Remember that
# your test database is "scratch space" for the test suite and is wiped
# and recreated between test runs. Don't rely on the data there!

require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # While tests run, we don't want to be logging to STDOUT
  config.logger = ActiveSupport::Logger.new(nil) if ENV["DISABLE_LOGS"]

  # Turn false under Spring and add config.action_view.cache_template_loading = true.
  config.enable_reloading = false

  # Eager loading loads your entire application. When running a single test locally,
  # this is usually not necessary, and can slow down your test suite. If you're using
  # a tool that preloads Rails, enable this for faster startup.
  config.eager_load = ENV["CI"].present?

  # Configure public file server for tests with Cache-Control for performance.
  config.public_file_server.enabled = true
  config.public_file_server.headers = {
    "Cache-Control" => "public, max-age=#{1.hour.to_i}"
  }

  # Show full error reports and disable caching.
  config.consider_all_requests_local = true
  config.action_controller.perform_caching = false
  config.cache_store = :null_store

  # Raise exceptions instead of rendering exception templates.
  config.action_dispatch.show_exceptions = :rescuable

  # Disable request forgery protection in test environment.
  config.action_controller.allow_forgery_protection = false

  # Store uploaded files on the local file system in a temporary directory.
  config.active_storage.service = :test

  config.action_mailer.perform_caching = false

  # Tell Action Mailer not to deliver emails to the real world.
  # The :test delivery method accumulates sent emails in the
  # ActionMailer::Base.deliveries array.
  config.action_mailer.delivery_method = :test
  config.action_mailer.default_url_options = { host: 'localhost', port: 3000 }

  # Print deprecation notices to the stderr.
  config.active_support.deprecation = :stderr

  # Raise exceptions for disallowed deprecations.
  config.active_support.disallowed_deprecation = :raise

  # Tell Active Support which deprecation messages to disallow.
  config.active_support.disallowed_deprecation_warnings = []

  # Raises error for missing translations.
  # config.i18n.raise_on_missing_translations = true

  # Annotate rendered view with file names.
  # config.action_view.annotate_rendered_view_with_filenames = true
  
  # Disable asset compilation in test mode
  config.assets.compile = false
  config.assets.debug = false
  config.assets.digest = false
  config.assets.enabled = false
  
  # Define test-specific settings for multi-tenancy
  config.x.multi_tenant.default_domain = 'example.com'
  config.x.multi_tenant.default_subdomain = 'test'
  
  # Set database configuration for tests
  config.active_record.migration_error = :page_load
  
  # Configure CSRF for testing
  config.action_controller.default_protect_from_forgery = true
end

# Disable ActiveAdmin initialization except the basics for tests
if defined?(ActiveAdmin)
  ActiveAdmin.setup do |config|
    config.skip_stylesheets_initialization = true if defined?(config.skip_stylesheets_initialization)
    config.skip_javascripts_initialization = true if defined?(config.skip_javascripts_initialization)
  end
end
