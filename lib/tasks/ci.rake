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
    
    business = Business.find_or_initialize_by(subdomain: 'consultllc')
    unless business.persisted?
      business.name = 'Consult LLC Performance Test'
      business.active = true
      business.industry = Business::SHOWCASE_INDUSTRY_MAPPINGS[:consulting]
      business.phone = '+1 (555) 555-5555'
      business.email = 'perf.business@example.com'
      business.address = '123 Test St'
      business.city = 'Testville'
      business.state = 'CA'
      business.zip = '90210'
      business.description = 'A test business for performance profiling.'
      business.tier = 'standard'
      business.host_type = 'subdomain'
      business.time_zone = 'UTC'
      # Set hostname to match subdomain - just lowercase letters, no dots or special chars
      business.hostname = 'consultllc'
      business.save(validate: false)
    end
    
    puts "Created/found business: #{business.name} (ID: #{business.id}, hostname: #{business.hostname})"
    
    puts "Creating performance test staff member..."
    staff = StaffMember.find_or_create_by!(business: business, email: 'perf_staff@example.com') do |s|
      s.name = 'Perf Staff'
      s.phone = '+1 (555) 555-5556'
      s.bio = 'Performance test staff member'
      s.active = true
      s.position = 'Test Position'
      # Set availability (required based on factory)
      s.availability = {
        'monday' => [{ 'start' => '09:00', 'end' => '17:00' }],
        'tuesday' => [{ 'start' => '09:00', 'end' => '17:00' }],
        'wednesday' => [{ 'start' => '09:00', 'end' => '17:00' }],
        'thursday' => [{ 'start' => '09:00', 'end' => '17:00' }],
        'friday' => [{ 'start' => '09:00', 'end' => '17:00' }],
        'saturday' => [],
        'sunday' => [],
        'exceptions' => {}
      }
    end
    
    puts "Creating performance test service..."
    # Don't force ID 3 - let database handle auto-increment
    service = Service.find_or_create_by!(
      business: business,
      name: 'Performance Test Service'
    ) do |s|
      s.description = 'Service for performance testing'
      s.duration = 60 # minutes
      s.price = 100.0
      s.active = true
      s.featured = false
      s.service_type = :standard
      # Based on factory, interval might be a property
      s.interval = 30 if s.respond_to?(:interval=)
    end
    
    puts "Created/found service: #{service.name} (ID: #{service.id})"
    
    # Ensure the staff member is associated with the service
    unless staff.services.include?(service)
      # Create the association through the join table
      ServicesStaffMember.find_or_create_by!(service: service, staff_member: staff)
      puts "Associated staff member #{staff.id} with service #{service.id}."
    end
    
    puts "Setting performance test staff availability..."
    # The availability was already set during creation, but we can update if needed
    puts "Staff member #{staff.id} already has weekly availability set."
    
    puts "Performance test data created successfully!"
    puts "Test URL will be: http://consultllc.lvh.me:3000/calendar?service_id=#{service.id}&commit=View+Availability"
  end
end