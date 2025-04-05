# frozen_string_literal: true

# This initializer configures Propshaft to properly handle ActiveAdmin assets
# and ensures assets are served correctly in production

if defined?(Propshaft)
  Rails.application.config.after_initialize do
    # Ensure ActiveAdmin assets are in Propshaft's load path
    if Rails.application.config.respond_to?(:assets) && 
       Rails.application.config.assets.respond_to?(:paths)
       
      # Log asset paths for debugging
      Rails.logger.info "Propshaft asset paths: #{Rails.application.config.assets.paths}"
      
      # Add the ActiveAdmin gem's asset paths
      if defined?(ActiveAdmin)
        begin
          activeadmin_path = Gem.loaded_specs['activeadmin'].full_gem_path
          Rails.application.config.assets.paths << File.join(activeadmin_path, 'app', 'assets', 'stylesheets')
          Rails.application.config.assets.paths << File.join(activeadmin_path, 'app', 'assets', 'javascripts')
          Rails.application.config.assets.paths << File.join(Rails.root, 'app', 'assets', 'builds')
          Rails.application.config.assets.paths << File.join(Rails.root, 'public', 'assets')
          
          Rails.logger.info "Added ActiveAdmin asset paths to Propshaft: #{activeadmin_path}"
        rescue => e
          Rails.logger.error "Failed to add ActiveAdmin asset paths: #{e.message}"
        end
      end
    end
  end
end 