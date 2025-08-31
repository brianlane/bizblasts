# frozen_string_literal: true

require "active_support/core_ext/integer/time"
require "securerandom"

# SECURITY FIX: Remove debug output that exposes sensitive information
# Debug output removed for security in production

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot. This eager loads most of Rails and
  # your application in memory, allowing both threaded web servers
  # and those relying on copy on write to perform better.
  # Rake tasks automatically ignore this option for performance.
  config.eager_load = true

  # Full error reports are disabled and caching is turned on.
  config.consider_all_requests_local = false
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }
  
  # Ensure public file server is enabled
  config.public_file_server.enabled = true
  
  # Propshaft assest config
  # Disable asset fingerprinting in production - we'll handle it manually -- trying to fix the asset pipeline
  config.assets.digest = true
  
  # Allow serving of static assets directly from public/assets
  config.assets.compile = false
  
  # # Set up static file serving directly
  # config.public_file_server.enabled = true
  # config.public_file_server.headers = {
  #   'Cache-Control' => 'public, max-age=31536000',
  #   'Expires' => 1.year.from_now.to_formatted_s(:rfc822)
  # }

  # # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # # config.asset_host = "http://assets.example.com"

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :amazon

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  config.assume_ssl = true

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = true

  # Devise
  config.action_mailer.default_url_options = { host: "bizblasts.com" }

  # ActionMailer configuration for Resend
  config.action_mailer.delivery_method = :resend
  config.action_mailer.perform_deliveries = true
  config.action_mailer.raise_delivery_errors = true
  config.action_mailer.default_url_options = { 
    host: "bizblasts.com",
    protocol: 'https'
  }
  
  # Default email options
  config.action_mailer.default_options = {
    from: ENV['MAILER_EMAIL']
  }

  # Log to STDOUT by default
  config.logger = ActiveSupport::Logger.new(STDOUT)
    .tap  { |logger| logger.formatter = ::Logger::Formatter.new }
    .then { |logger| ActiveSupport::TaggedLogging.new(logger) }

  # Prepend all log lines with the following tags.
  config.log_tags = [ :request_id ]

  # Info include generic and useful information about system operation, but avoids logging too much
  # information to avoid inadvertent exposure of personally identifiable information (PII).
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  config.cache_store = :solid_cache_store

  # Replace the default in-process and non-durable queuing backend for Active Job.
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }
  
  # Configure standard ActionCable
  config.action_cable.mount_path = '/cable'
  config.action_cable.url = "wss://bizblasts.onrender.com/cable"
  config.action_cable.allowed_request_origins = [
    "https://bizblasts.onrender.com", 
    "http://bizblasts.onrender.com",
    "https://www.bizblasts.com",
    "http://www.bizblasts.com",
    "https://bizblasts.com",
    "http://bizblasts.com",
    # Allow Render PR preview URLs
    /https:\/\/bizblasts-pr-\d+\.onrender\.com/,
    /http:\/\/bizblasts-pr-\d+\.onrender\.com/
  ]
  
  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [:id]

  # Default allowed hosts are set in `config/application.rb`. Additional
  # custom domains are added at runtime via
  # `config/initializers/custom_domain_hosts.rb`.
  
  # Skip DNS rebinding protection for health check endpoints to allow Render
  # readiness probes to succeed even before custom hosts are fully loaded.
  config.host_authorization = {
    exclude: ->(request) { ["/up", "/healthcheck"].include?(request.path) }
  }
end