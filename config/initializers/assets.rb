# frozen_string_literal: true

# This initializer sets up Rails asset configuration

# Be sure to restart your server when you modify this file.

# Add additional assets to the asset load path.
Rails.application.config.assets.paths ||= []

# Add node_modules directory as asset path if present
Rails.application.config.assets.paths << Rails.root.join('node_modules').to_s if Dir.exist?(Rails.root.join('node_modules'))

# Add Yarn node_modules directory as asset path if present (CI environments)
if defined?(Rails.root.join('vendor', 'node_modules'))
  yarn_path = Rails.root.join('vendor', 'node_modules')
  Rails.application.config.assets.paths << yarn_path.to_s if Dir.exist?(yarn_path)
end

# Add app/assets/builds to asset path for compiled assets
Rails.application.config.assets.paths << Rails.root.join('app', 'assets', 'builds').to_s

# Add public/assets to asset path (needed for production)
Rails.application.config.assets.paths << Rails.root.join('public', 'assets').to_s

# Add specific paths for assets that might be hard to find
Rails.application.config.assets.precompile += %w(
  active_admin.css
  active_admin.js
  application.css
  application.js
)