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
    
    # Create test data for performance profiling
    puts "Creating performance test data..."
    Rake::Task["ci:create_performance_test_data"].invoke
    
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

# Task to create necessary test data for performance profiling
namespace :ci do
  desc "Create performance test data (business, staff, service, availability)"
  task create_performance_test_data: :environment do
    puts "Creating performance test business..."
    business = Business.find_or_create_by!(subdomain: 'consultllc') do |b|
      b.name = 'Consult LLC Performance Test'
      b.hostname = 'consultllc.lvh.me'
      b.status = 'active'
      b.account_status = 'active'
      # Add any other required business attributes
    end
    
    puts "Creating performance test staff member..."
    staff = StaffMember.find_or_create_by!(business: business, email: 'perf_staff@example.com') do |s|
      s.first_name = 'Perf'
      s.last_name = 'Staff'
      s.status = 'active'
      s.user_id = nil # Staff member doesn't need a user account for this test data
      # Add any other required staff attributes
    end
    
    puts "Creating performance test service (ID 3)..."
    # Try to create with ID 3, but let DB handle auto-increment if ID is taken
    service = Service.find_by(id: 3) # Check if ID 3 already exists
    if service.nil?
      service = Service.create!(
        id: 3, # Attempt to use ID 3
        business: business,
        name: 'Performance Test Service',
        description: 'Service for performance testing',
        duration: 60, # minutes
        interval: 30, # minutes
        price: 100.0,
        status: 'active'
        # Add any other required service attributes
      )
    elsif service.business != business || service.name != 'Performance Test Service'
      # If ID 3 exists but belongs to a different business or is not our test service, find or create a different one
      puts "Service with ID 3 exists and is not the performance test service. Creating a new one."
      service = Service.find_or_create_by!(business: business, name: 'Performance Test Service') do |s|
        s.description = 'Service for performance testing'
        s.duration = 60
        s.interval = 30
        s.price = 100.0
        s.status = 'active'
      end
    else
      puts "Service with ID 3 already exists and belongs to performance test business."
      # Update attributes if necessary
      service.update!(
        description: 'Service for performance testing',
        duration: 60,
        interval: 30,
        price: 100.0,
        status: 'active'
      )
    end
    
    # Ensure the staff member is associated with the service
    unless staff.services.include?(service)
      staff.services << service
      puts "Associated staff member #{staff.id} with service #{service.id}."
    end
    
    puts "Setting performance test staff availability..."
    # Set availability for a range of dates around 2025-01-01
    availability_start_date = Date.parse('2024-12-29')
    availability_end_date = Date.parse('2025-01-05')
    availability_data = {
      'monday' => [{ 'start' => '09:00', 'end' => '17:00' }],
      'tuesday' => [{ 'start' => '09:00', 'end' => '17:00' }],
      'wednesday' => [{ 'start' => '09:00', 'end' => '17:00' }],
      'thursday' => [{ 'start' => '09:00', 'end' => '17:00' }],
      'friday' => [{ 'start' => '09:00', 'end' => '17:00' }],
      'saturday' => [],
      'sunday' => []
    }
    
    # Apply general weekly availability
    staff.availability = availability_data
    staff.save!
    puts "Set weekly availability for staff member #{staff.id}."
    
    # Optionally, add exceptions for specific dates if needed
    # Example: add an exception for 2025-01-01 if it's a holiday
    # staff.availability['exceptions'] ||= {}
    # staff.availability['exceptions']['2025-01-01'] = [] # No availability on Jan 1st
    # staff.save!
  end
end