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
    
    # Now run the actual schema load
    puts "Loading database schema..."
    Rake::Task["db:schema:load"].invoke
    
    puts "CI database setup complete!"
  end
end 