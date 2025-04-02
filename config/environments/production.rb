# frozen_string_literal: true

require "active_support/core_ext/integer/time"
require "securerandom"

# Set a default secret key base if not provided by environment
# Rails.application.config.secret_key_base = ENV["SECRET_KEY_BASE"]

# Debug output for database configuration
puts "DATABASE_URL environment variable: #{ENV['DATABASE_URL'] ? 'Set (value hidden for security)' : 'NOT SET'}"
puts "DATABASE_HOST environment variable: #{ENV['DATABASE_HOST'] || 'NOT SET'}"
puts "DATABASE_PORT environment variable: #{ENV['DATABASE_PORT'] ? ENV['DATABASE_PORT'] : 'NOT SET (using default 5432)'}"
puts "SECRET_KEY_BASE set: #{ENV['SECRET_KEY_BASE'] ? 'Yes' : 'No'}"
puts "RAILS_MASTER_KEY set: #{ENV['RAILS_MASTER_KEY'] ? 'Yes' : 'No'}"

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

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  config.assume_ssl = true

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = true

  # Devise
  config.action_mailer.default_url_options = { host: "bizblasts.com" }

  # Skip http-to-https redirect for the default health check endpoint.
  # config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

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
  
  # Configure standard ActionCable
  config.action_cable.mount_path = '/cable'
  config.action_cable.url = "wss://bizblasts.onrender.com/cable"
  config.action_cable.allowed_request_origins = [
    "https://bizblasts.onrender.com", 
    "http://bizblasts.onrender.com",
    "https://www.bizblasts.com",
    "http://www.bizblasts.com",
    "https://bizblasts.com",
    "http://bizblasts.com"
  ]
  
  # Ignore bad email addresses and do not raise email delivery errors.
  # Set this to true and configure the email server for immediate delivery to raise delivery errors.
  # config.action_mailer.raise_delivery_errors = false

  # Set host to be used by links generated in mailer templates.
  config.action_mailer.default_url_options = { host: "www.bizblasts.com" }

  # Specify outgoing SMTP server. Remember to add smtp/* credentials via rails credentials:edit.
  # config.action_mailer.smtp_settings = {
  #   user_name: Rails.application.credentials.dig(:smtp, :user_name),
  #   password: Rails.application.credentials.dig(:smtp, :password),
  #   address: "smtp.example.com",
  #   port: 587,
  #   authentication: :plain
  # }

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [:id]

  # Enable DNS rebinding protection and other `Host` header attacks.
  config.hosts = [
    "bizblasts.onrender.com",
    "bizblasts.com",
    "www.bizblasts.com"
  ]
  
  # Skip DNS rebinding protection for the default health check endpoint.
  config.host_authorization = { exclude: ->(request) { request.path == "/up" } }

  # Only use ENV["SECRET_KEY_BASE"] directly to avoid conflicts with credentials system
  # Do not generate random values as this will cause session corruption between restarts
  config.secret_key_base = ENV["SECRET_KEY_BASE"]
end
