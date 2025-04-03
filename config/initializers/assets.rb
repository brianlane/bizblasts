# frozen_string_literal: true

# Be sure to restart your server when you modify this file.

# Version of your assets, change this if you want to expire all your assets.
Rails.application.config.assets.version = "1.0"

# Add additional assets to the asset load path.
# Rails.application.config.assets.paths << Rails.root.join("node_modules")

# Prevent Propshaft error when used with Sprockets in test mode
# Disable sprockets-rails in test environment to avoid the Propshaft conflict
if Rails.env.test? || ENV['RAILS_DISABLE_ASSET_COMPILATION'] == 'true' || ENV['DISABLE_PROPSHAFT'] == 'true'
  # Completely disable asset compilation
  Rails.application.config.assets.compile = false
  Rails.application.config.assets.digest = false
  Rails.application.config.assets.debug = false
  Rails.application.config.assets.quiet = true
  
  # Change asset prefix to avoid any conflicts
  Rails.application.config.after_initialize do
    Rails.application.config.assets.prefix = "/ignored-assets-for-test"
    
    # If propshaft is defined, disable it completely
    if defined?(Propshaft) && defined?(Rails.application.config.propshaft)
      Rails.application.config.propshaft.compilers = []
      Rails.application.config.propshaft.paths = []
    end
  end
  
  # Use a simpler manifest format 
  Rails.application.config.assets.manifest = nil
end
