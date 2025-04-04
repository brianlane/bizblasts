# frozen_string_literal: true

namespace :test do
  desc "Optimize database for testing"
  task optimize: :environment do
    puts "Optimizing database for testing..."
    
    # Only run in test environment
    unless Rails.env.test?
      puts "This task should only be run in the test environment."
      exit 1
    end
    
    # Disable statement timeout for optimization
    ActiveRecord::Base.connection.execute("SET statement_timeout = 0;")
    
    # First, reindex all tables to improve database performance
    puts "Reindexing all tables..."
    ActiveRecord::Base.connection.tables.each do |table|
      puts "  Reindexing #{table}..."
      ActiveRecord::Base.connection.execute("REINDEX TABLE #{table};")
    end
    
    # Analyze tables to update statistics
    puts "Analyzing all tables..."
    ActiveRecord::Base.connection.execute("ANALYZE;")
    
    # Set synchronous_commit to off for faster writes
    puts "Setting synchronous_commit to off..."
    ActiveRecord::Base.connection.execute("SET synchronous_commit = off;")
    
    # Increase work memory for better query performance
    puts "Increasing work memory..."
    ActiveRecord::Base.connection.execute("SET work_mem = '16MB';")
    
    puts "Optimization complete!"
  end
  
  desc "Run tests with optimized database"
  task :optimized do
    Rake::Task["test:optimize"].invoke
    Rake::Task["test"].invoke
  end
end 