namespace :db do
  desc "Test database connection and show configuration"
  task test_connection: :environment do
    puts "Rails Environment: #{Rails.env}"
    puts "Database Configuration:"
    puts "======================="
    
    # Get the configuration from database.yml
    db_config = ActiveRecord::Base.connection_db_config.configuration_hash
    puts "Adapter: #{db_config[:adapter]}"
    puts "Database: #{db_config[:database]}"
    puts "Host: #{db_config[:host]}"
    puts "Port: #{db_config[:port]}"
    puts "Username: #{db_config[:username]}"
    puts "Use URL: #{db_config[:url].present? ? 'Yes' : 'No'}"
    puts "Host type: #{db_config[:host_type]}"
    
    # Try to connect
    begin
      # Try a simple query
      result = ActiveRecord::Base.connection.execute("SELECT current_timestamp")
      timestamp = result.first["current_timestamp"]
      puts "\nConnection successful!"
      puts "Database server time: #{timestamp}"
      
      # Show SolidCache configuration
      if defined?(SolidCache)
        puts "\nSolidCache Configuration:"
        puts "========================="
        puts "Store type: #{Rails.application.config.cache_store}"
        puts "SolidCache available: Yes"
      end
      
      # Show SolidQueue configuration
      if defined?(SolidQueue)
        puts "\nSolidQueue Configuration:"
        puts "========================="
        puts "Queue adapter: #{Rails.application.config.active_job.queue_adapter}"
      end
      
    rescue => e
      puts "\nConnection failed: #{e.message}"
      puts e.backtrace.first(10)
    end
  end
  
  desc "Test production database connection (run with RAILS_ENV=production)"
  task test_production_connection: :environment do
    unless Rails.env.production?
      puts "This task must be run with RAILS_ENV=production"
      puts "Example: RAILS_ENV=production bundle exec rake db:test_production_connection"
      exit 1
    end
    
    puts "Testing production database connection..."
    puts "DATABASE_URL: #{ENV['DATABASE_URL'] ? 'Set (value hidden)' : 'NOT SET'}"
    puts "DATABASE_HOST: #{ENV.fetch('DATABASE_HOST', nil)}"
    puts "DATABASE_PORT: #{ENV.fetch('DATABASE_PORT', nil)}"
    puts "DATABASE_NAME: #{ENV.fetch('DATABASE_NAME', nil)}"
    puts "DATABASE_USERNAME: #{ENV['DATABASE_USERNAME'] ? 'Set (value hidden)' : 'NOT SET'}"
    puts "DATABASE_PASSWORD: #{ENV['DATABASE_PASSWORD'] ? 'Set (value hidden)' : 'NOT SET'}"
    
    begin
      # Try to connect
      ActiveRecord::Base.establish_connection
      ActiveRecord::Base.connection.execute("SELECT 1 as test")
      puts "Connection successful! Database is available."
      puts "Database adapter: #{ActiveRecord::Base.connection.adapter_name}"
      puts "Database version: #{ActiveRecord::Base.connection.execute("SELECT version()").first['version']}"
    rescue => e
      puts "Connection failed: #{e.message}"
      puts e.backtrace.first(5)
    end
  end
end
