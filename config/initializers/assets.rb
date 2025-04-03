# frozen_string_literal: true

# Be sure to restart your server when you modify this file.

# Version of your assets, change this if you want to expire all your assets.
Rails.application.config.assets.version = "1.0"

# Add additional assets to the asset load path.
# Rails.application.config.assets.paths << Rails.root.join("node_modules")

# Prevent Propshaft error when used with Sprockets in test mode
# Disable sprockets-rails in test environment to avoid the Propshaft conflict
if Rails.env.test?
  Rails.application.config.assets.compile = false
  
  Rails.application.config.after_initialize do
    Rails.application.config.assets.prefix = "/ignored-assets-for-test"
  end
end
