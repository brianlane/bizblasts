# frozen_string_literal: true

# This initializer runs very early (hence the 000_ prefix)
# to ensure Sprockets is properly patched before any other code uses it

if Rails.env.test? && ENV['DISABLE_PROPSHAFT'] == 'true'
  puts "Applying early Sprockets/Propshaft conflict fix..."
  
  begin
    require 'sprockets/manifest'
    
    # Only patch if not already patched
    unless Sprockets::Manifest.instance_methods.include?(:original_initialize)
      Sprockets::Manifest.class_eval do
        alias_method :original_initialize, :initialize
        
        # Accept any argument pattern
        def initialize(*args)
          if ENV['SPROCKETS_DEBUG'] == 'true'
            puts "Sprockets::Manifest#initialize called with #{args.inspect}"
          end
          
          env = args[0]
          dir = args[1]
          
          # Default values
          @environment = env
          @directory = nil
          @filename = "manifest.json"
          
          # Handle Propshaft::Assembly or other non-string directory
          if dir && dir.respond_to?(:to_s)
            begin
              dir_str = dir.to_s
              @directory = File.expand_path(dir_str) if dir_str.is_a?(String)
            rescue => e
              puts "Warning: Could not convert directory to string: #{e.message}" if ENV['SPROCKETS_DEBUG'] == 'true'
            end
          end
        end
      end
      
      puts "Sprockets::Manifest successfully patched."
    end
  rescue LoadError => e
    puts "Could not load sprockets/manifest: #{e.message}"
  rescue => e
    puts "Failed to patch Sprockets::Manifest: #{e.message}"
  end
end 