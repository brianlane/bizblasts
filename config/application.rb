# frozen_string_literal: true

require_relative "boot"

require "rails/all"

# Remove the Rails initializer that sets autoload_paths to avoid frozen array modification
#Rails::Engine.initializers.delete_if { |init| init.name.to_s == "set_autoload_paths" }

# Explicitly require acts_as_tenant early
# require "acts_as_tenant"


# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Bizblasts
  # Main application configuration class for Bizblasts
  # Handles all Rails configuration settings and middleware setup
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0
    # Configure main domain for multi-tenant OAuth redirects
    config.main_domain = Rails.env.production? ? 'bizblasts.com' : 'lvh.me'

    # Explicitly add ActsAsTenant middleware by requiring its specific file
    # require "acts_as_tenant/middleware" # Reverted - Let gem handle it
    # config.middleware.use ActsAsTenant::Middleware # Reverted - Let gem handle it

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # For example, adding `lib` to the `$LOAD_PATH`.
    # config.autoload_lib(ignore: %w(assets tasks))
    config.autoload_paths << Rails.root.join("lib")

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
    
    # Add app/lib directory to autoload paths for security utilities
    config.eager_load_paths << Rails.root.join("app", "lib")
    
    # SMS Configuration
    config.sms_enabled = ActiveModel::Type::Boolean.new.cast(ENV.fetch('ENABLE_SMS', 'true'))

    # Add app/assets/stylesheets to the asset load path
    config.assets.paths << Rails.root.join("app/assets/stylesheets")

    # Handle subdomain-based tenancy
    config.hosts << /.+\.lvh\.me/
    config.hosts << /.+\.bizblasts\.com/
    config.hosts << /.+\.bizblasts\.onrender\.com/
    # Main platform domains (add apex + www to cover redirects)
    [
      "bizblasts.com",
      "www.bizblasts.com",
      "bizblasts.onrender.com"
    ].each { |h| config.hosts << h }
    # Allow Render PR preview URLs (format: bizblasts-pr-XX.onrender.com)
    config.hosts << /bizblasts-pr-\d+\.onrender\.com/

    # Image processing configuration for large uploads
    config.active_storage.variant_processor = :mini_magick
    
    # Configure large file upload timeouts
    config.active_job.queue_adapter = :solid_queue
    
    # Increase Rack timeout for large file uploads (2 minutes)
    config.force_ssl = false unless Rails.env.production?

    # SECURITY FIX: Add rack-attack middleware for rate limiting
    config.middleware.use Rack::Attack

    # Set the start of the week to Sunday for consistency across the app
    config.beginning_of_week = :sunday

    # Configure Active Record encryption to use environment variables
    if ENV['ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY'].present?
      config.active_record.encryption.primary_key = ENV['ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY']
      config.active_record.encryption.deterministic_key = ENV['ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY']
      config.active_record.encryption.key_derivation_salt = ENV['ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT']
    end
  end
end
