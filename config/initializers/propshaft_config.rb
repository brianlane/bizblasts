# frozen_string_literal: true

# Simple Propshaft configuration to prevent asset conflicts with ActiveAdmin
Rails.application.configure do
  # Exclude ActiveAdmin's gem assets to prevent circular dependencies
  # Only process our built assets, not the raw gem assets
  config.assets.paths = [Rails.root.join('app', 'assets', 'builds')]
  
  # Let Propshaft handle fingerprinting normally
  config.assets.digest = true
  config.assets.compile = false

# # This initializer configures Propshaft to properly handle ActiveAdmin assets
# # and ensures assets are served correctly in production

# # Make sure paths are set up before the app loads
# if defined?(Propshaft)
#   # Register ActiveAdmin asset paths with Propshaft immediately, rather than waiting for after_initialize
#   Rails.application.config.assets.paths ||= []
#   puts "Setting up Propshaft asset paths for ActiveAdmin..."
  
#   # Add app/assets/builds directory to load path
#   Rails.application.config.assets.paths << Rails.root.join('app', 'assets', 'builds').to_s
  
#   # Add public/assets directory to load path
#   Rails.application.config.assets.paths << Rails.root.join('public', 'assets').to_s
  
#   # Add the ActiveAdmin gem's asset paths
#   if defined?(ActiveAdmin) || Gem.loaded_specs.key?('activeadmin')
#     begin
#       activeadmin_path = Gem.loaded_specs['activeadmin'].full_gem_path
#       Rails.application.config.assets.paths << File.join(activeadmin_path, 'app', 'assets', 'stylesheets')
#       Rails.application.config.assets.paths << File.join(activeadmin_path, 'app', 'assets', 'javascripts')
#       puts "Added ActiveAdmin asset paths: #{activeadmin_path}"
#     rescue => e
#       puts "Failed to add ActiveAdmin asset paths: #{e.message}"
#     end
#   end
  
#   # Disable fingerprinting in production - we'll handle asset versioning manually
#   if Rails.env.production?
#     begin
#       if Rails.application.config.respond_to?(:assets)
#         Rails.application.config.assets.digest = false
#         puts "Disabled asset fingerprinting in production to avoid issues with ActiveAdmin"
#       end
#     rescue => e
#       puts "Failed to disable asset fingerprinting: #{e.message}"
#     end
#   end
  
  # Register specific paths for ActiveAdmin CSS files
  # This ensures they're findable regardless of precompilation
  # The following block is removed because compute_path no longer exists in Propshaft and causes errors.
  # Rails.application.config.after_initialize do
  #   # Print asset paths to logs for debugging
  #   Rails.logger.info "Propshaft asset paths: #{Rails.application.config.assets.paths.inspect}"
  #   # Special handling for ActiveAdmin assets in production
  #   if Rails.env.production?
  #     if Rails.application.respond_to?(:assets) && Rails.application.assets.respond_to?(:define_singleton_method)
  #       begin
  #         original_compute_path = Rails.application.assets.method(:compute_path)
  #         Rails.application.assets.define_singleton_method(:compute_path) do |path, **options|
  #           if path == "active_admin.css"
  #             Rails.root.join('public', 'assets', 'active_admin.css').to_s
  #           elsif path == "application.css"
  #             Rails.root.join('public', 'assets', 'application.css').to_s
  #           elsif path == "application.js"
  #             Rails.root.join('public', 'assets', 'application.js').to_s
  #           else
  #             original_compute_path.call(path, **options)
  #           end
  #         end
  #         Rails.logger.info "Added special handling for asset path computation"
  #       rescue => e
  #         Rails.logger.error "Failed to add special handling for assets: #{e.message}"
  #       end
  #     end
  #   end
  # end
end 