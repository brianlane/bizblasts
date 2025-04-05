# frozen_string_literal: true

# This initializer configures Propshaft to properly handle ActiveAdmin assets
# and ensures assets are served correctly in production

# Make sure paths are set up before the app loads
if defined?(Propshaft)
  # Register ActiveAdmin asset paths with Propshaft immediately, rather than waiting for after_initialize
  Rails.application.config.assets.paths ||= []
  puts "Setting up Propshaft asset paths for ActiveAdmin..."
  
  # Add app/assets/builds directory to load path
  Rails.application.config.assets.paths << Rails.root.join('app', 'assets', 'builds').to_s
  
  # Add public/assets directory to load path
  Rails.application.config.assets.paths << Rails.root.join('public', 'assets').to_s
  
  # Add the ActiveAdmin gem's asset paths
  if defined?(ActiveAdmin) || Gem.loaded_specs.key?('activeadmin')
    begin
      activeadmin_path = Gem.loaded_specs['activeadmin'].full_gem_path
      Rails.application.config.assets.paths << File.join(activeadmin_path, 'app', 'assets', 'stylesheets')
      Rails.application.config.assets.paths << File.join(activeadmin_path, 'app', 'assets', 'javascripts')
      puts "Added ActiveAdmin asset paths: #{activeadmin_path}"
    rescue => e
      puts "Failed to add ActiveAdmin asset paths: #{e.message}"
    end
  end
  
  # Also register with after_initialize to ensure paths are available
  Rails.application.config.after_initialize do
    # Print asset paths to logs for debugging
    Rails.logger.info "Propshaft asset paths: #{Rails.application.config.assets.paths.inspect}"
  end
end 