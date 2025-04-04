# frozen_string_literal: true

# Be sure to restart your server when you modify this file.

# Version of your assets, change this if you want to expire all your assets.
Rails.application.config.assets.version = "1.0"

# Add additional assets to the asset load path.
# Rails.application.config.assets.paths << Rails.root.join("node_modules")

# Prevent Propshaft error when used with Sprockets in test mode
# Configure test environment assets in a way that avoids Propshaft/Sprockets conflicts
if Rails.env.test?
  Rails.application.config.assets.compile = false
  
  # Use a prefix that won't conflict with actual asset paths
  Rails.application.config.assets.prefix = "/test-assets"
  
  # Disable digest for test environment
  Rails.application.config.assets.digest = false
end
