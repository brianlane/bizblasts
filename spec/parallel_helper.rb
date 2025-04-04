# frozen_string_literal: true

require 'bundler/setup' # Ensure Bundler loads correct groups for parallel env
require_relative '../config/environment'
require 'parallel_tests/tasks' # Ensure parallel tasks are loaded
require 'rake' # Require Rake

# Load the Rails application tasks
Rails.application.load_tasks

puts "--- [Parallel Helper] Running one-time setup using Rake tasks... ---"

# 1. Prepare the test databases using parallel_tests task
begin
  puts "--- [Parallel Helper] Preparing parallel databases with parallel:prepare... ---"
  Rake::Task['parallel:prepare'].invoke
  puts "--- [Parallel Helper] Parallel databases prepared. ---"
rescue => e
  puts "--- [Parallel Helper] ERROR preparing parallel databases: #{e.message} ---"
  raise e # Re-raise error to halt tests if setup fails
end

# 2. Seed the primary test database directly
# begin
#   puts "--- [Parallel Helper] Loading seeds with Rails.application.load_seed... ---"
#   # Ensure environment is loaded for direct seeding
#   require Rails.root.join('config/environment') 
#   Rails.application.load_seed
#   puts "--- [Parallel Helper] Seeds seemingly loaded. ---"
# rescue => e
#   puts "--- [Parallel Helper] ERROR loading seeds directly: #{e.message} ---"
#   puts e.backtrace.join("\n") # Print backtrace for seed errors
#   raise e # Re-raise error to halt tests if seeding fails
# end

# Verify seeds are visible before proceeding
# puts "--- [Parallel Helper] Verifying seed data visibility... ---"
# max_seed_wait = 10 # seconds
# wait_interval = 0.5 # seconds
# start_wait = Time.now
# seeds_visible = false
# while Time.now - start_wait < max_seed_wait
#   begin
#     # Use a fresh connection to check visibility
#     connection = ActiveRecord::Base.connection_pool.checkout
#     if connection.select_value("SELECT 1 FROM businesses WHERE subdomain = 'default' LIMIT 1") == 1
#       seeds_visible = true
#       break
#     end
#   rescue => e
#     puts "--- [Parallel Helper] WARN: Error checking seed visibility: #{e.message} ---" 
#   ensure
#     ActiveRecord::Base.connection_pool.checkin(connection) if connection
#   end
#   sleep wait_interval
# end

# unless seeds_visible
#   raise "--- [Parallel Helper] FATAL: Seed data (default business) not visible after #{max_seed_wait} seconds! Halting tests. ---"
# end
# puts "--- [Parallel Helper] Seed data verified. Proceeding with tests. ---"

puts "--- [Parallel Helper] One-time setup complete. ---" 