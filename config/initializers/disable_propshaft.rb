# frozen_string_literal: true

# This initializer handles conflicts between Propshaft and Sprockets
# when running in test environment, especially in CI

if Rails.env.test? && ENV['DISABLE_PROPSHAFT'].present?
  # Remove Propshaft from the middleware stack if it's present
  if defined?(Propshaft) && Rails.application.config.respond_to?(:assets)
    Rails.application.config.assets.compile = false
    
    # If Sprockets is loaded, ensure it's configured correctly
    if defined?(Sprockets)
      # Ensure Sprockets manifest can handle nil or Propshaft assembly
      unless Sprockets::Manifest.instance_methods.include?(:original_initialize)
        Sprockets::Manifest.class_eval do
          alias_method :original_initialize, :initialize
          
          # Use a more flexible argument pattern that works with any number of arguments
          def initialize(*args)
            env = args[0]
            dir = args[1]
            
            # Handle Propshaft::Assembly by checking if dir responds to :to_s
            if dir.nil? || (dir.respond_to?(:to_s) && dir.to_s.is_a?(String))
              @environment = env
              @directory = dir.nil? ? nil : File.expand_path(dir.to_s)
              @filename = "manifest.json"
            else
              # If dir is something unusual (like Propshaft::Assembly), use empty settings
              @environment = env
              @directory = nil
              @filename = "manifest.json"
            end
          end
        end
      end
    end
  end
end 