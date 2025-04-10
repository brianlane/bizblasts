# frozen_string_literal: true

require_relative "boot"

require "rails/all"
# # Pick the frameworks you want:
# require "active_model/railtie"
# require "active_job/railtie"
# require "active_record/railtie"
# # require "active_storage/engine"
# require "action_controller/railtie"
# require "action_mailer/railtie"
# # require "action_mailbox/engine"
# # require "action_text/engine"
# require "action_view/railtie"
# require "action_cable/engine"
# # require "sprockets/railtie"
# # require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Bizblasts
  # Main application configuration class for Bizblasts
  # Handles all Rails configuration settings and middleware setup
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
    
    # Ensure asset paths are set up early for Propshaft
    if defined?(Propshaft)
      config.assets.paths ||= []
      
      # Add app/assets/builds to the asset load path
      config.assets.paths << Rails.root.join('app', 'assets', 'builds').to_s
      
      # Add public/assets to the asset load path for production fallbacks
      config.assets.paths << Rails.root.join('public', 'assets').to_s
      
      # Add ActiveAdmin asset paths
      begin
        aa_path = Bundler.rubygems.find_name('activeadmin').first.full_gem_path
        config.assets.paths << File.join(aa_path, 'app', 'assets', 'stylesheets')
        puts "Added ActiveAdmin asset paths: #{File.join(aa_path, 'app', 'assets', 'stylesheets')}" # Added puts for debugging CI
      rescue Bundler::GemNotFound
        warn "ActiveAdmin gem not found. Skipping asset path configuration."
      end
    end
  end
end
