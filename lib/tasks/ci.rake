# frozen_string_literal: true

namespace :ci do
  desc "Set up database for CI with asset conflicts handled"
  task setup: :environment do
    # Ensure Propshaft is disabled
    ENV['DISABLE_PROPSHAFT'] = 'true'
    ENV['RAILS_DISABLE_ASSET_COMPILATION'] = 'true'
    
    # Fix Sprockets conflict with Propshaft if needed
    if defined?(Sprockets) && defined?(Propshaft)
      puts "Fixing Sprockets/Propshaft conflict..."
      # Handle the conflict directly
      Sprockets::Manifest.class_eval do
        # Only override if not already overridden
        unless instance_methods.include?(:original_initialize)
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
    
    # Now run the actual schema load
    puts "Loading database schema..."
    Rake::Task["db:schema:load"].invoke
    
    puts "CI database setup complete!"
  end
end 