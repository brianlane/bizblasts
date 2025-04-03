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
          
          def initialize(environment, dir = nil, **options)
            if dir.is_a?(String) || dir.nil?
              @directory = dir ? File.expand_path(dir) : nil
              @environment = environment
              @filename = options[:filename] || "manifest.json"
            else
              # If dir is not a string (e.g., Propshaft::Assembly), use empty settings
              @directory = nil
              @environment = environment
              @filename = "manifest.json"
            end
          end
        end
      end
    end
  end
end 