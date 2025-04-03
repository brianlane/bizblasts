# frozen_string_literal: true

namespace :ci do
  desc "Full GitHub Actions setup - handles everything in the right order"
  task github_actions: :environment do
    # Set environment variables
    ENV['DISABLE_PROPSHAFT'] = 'true'
    ENV['RAILS_DISABLE_ASSET_COMPILATION'] = 'true'
    ENV['DISABLE_DATABASE_ENVIRONMENT_CHECK'] = '1'
    
    # Fix asset conflicts first
    puts "Setting up CI environment..."
    Rake::Task["ci:setup"].invoke
    
    # Create database if it doesn't exist
    puts "Setting up database..."
    begin
      ActiveRecord::Base.connection
    rescue ActiveRecord::NoDatabaseError
      puts "Database doesn't exist, creating..."
      Rake::Task["db:create"].invoke
    rescue => e
      puts "Error connecting to database: #{e.message}, attempting to create..."
      Rake::Task["db:create"].invoke rescue nil
    end
    
    # Run migrations (only once)
    puts "Running database migrations..."
    begin
      Rake::Task["db:migrate"].invoke
    rescue => e
      puts "Migration error: #{e.message}"
      # Only if migration fails, try a fresh database
      Rake::Task["db:drop"].invoke rescue nil
      Rake::Task["db:create"].invoke
      Rake::Task["db:migrate"].invoke
    end
    
    # Seed the database (only after migrations are complete)
    puts "Seeding test database..."
    Rake::Task["db:seed"].invoke
    
    puts "GitHub Actions setup complete and ready for testing!"
  end

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
    
    # Ensure the database is properly set up
    setup_database
    
    puts "CI database setup complete!"
  end
  
  desc "Run all database setup commands to ensure schema is ready"
  task reset_db: :environment do
    setup_database(force: true)
  end
  
  # Helper method to set up the database
  def setup_database(force: false)
    # Check for the database connection
    begin
      ActiveRecord::Base.connection
    rescue ActiveRecord::NoDatabaseError
      # Create the database if it doesn't exist
      puts "Database doesn't exist, creating..."
      Rake::Task["db:create"].invoke
    rescue => e
      puts "Error connecting to database: #{e.message}"
      # Force create the database
      puts "Attempting to create database anyway..."
      Rake::Task["db:create"].invoke
    end
    
    # Try running migrations first
    begin
      if force
        puts "Forcing database reset..."
        Rake::Task["db:drop"].invoke if ActiveRecord::Base.connection.table_exists?('schema_migrations')
        Rake::Task["db:create"].invoke
      end
      
      puts "Running database migrations..."
      Rake::Task["db:migrate"].invoke
    rescue ActiveRecord::NoDatabaseError
      puts "Database doesn't exist, creating and migrating..."
      Rake::Task["db:create"].invoke
      Rake::Task["db:migrate"].invoke
    rescue ActiveRecord::StatementInvalid => e
      puts "SQL error: #{e.message}, attempting to load schema..."
      # If there's a SQL error, try loading the schema
      begin
        Rake::Task["db:schema:load"].invoke
      rescue => schema_error
        puts "Schema load failed: #{schema_error.message}, doing full reset..."
        Rake::Task["db:drop"].invoke rescue nil
        Rake::Task["db:create"].invoke
        Rake::Task["db:migrate"].invoke
      end
    rescue => e
      puts "Migration error: #{e.message}, attempting full reset..."
      Rake::Task["db:drop"].invoke rescue nil
      Rake::Task["db:create"].invoke
      Rake::Task["db:migrate"].invoke
    end
  end
end 