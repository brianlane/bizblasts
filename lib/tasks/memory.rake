# Memory profiling and monitoring tasks
# frozen_string_literal: true

namespace :memory do
  desc "Profile memory usage of the application"
  task profile: :environment do
    puts "\n=== Rails Application Memory Profile ==="
    puts "Environment: #{Rails.env}"
    puts "Time: #{Time.current}"
    
    # Basic memory stats
    memory_mb = `ps -o rss= -p #{Process.pid}`.to_i / 1024
    puts "Current Memory Usage: #{memory_mb}MB"
    
    if defined?(ObjectSpace)
      # Object space statistics
      objects = ObjectSpace.count_objects
      puts "\nObject Counts:"
      puts "  Total Objects: #{objects[:TOTAL]}"
      puts "  Free Objects: #{objects[:FREE]}"
      puts "  Strings: #{objects[:T_STRING]}"
      puts "  Arrays: #{objects[:T_ARRAY]}"
      puts "  Hashes: #{objects[:T_HASH]}"
      puts "  Classes: #{objects[:T_CLASS]}"
      puts "  Modules: #{objects[:T_MODULE]}"
    end
    
    # ActiveRecord connection pool stats
    puts "\nActiveRecord Connection Pools:"
    ActiveRecord::Base.connection_pool_list.each do |pool|
      puts "  #{pool.db_config.name}: #{pool.stat}"
    end
    
    # SolidQueue stats if available
    if defined?(SolidQueue) && ActiveRecord::Base.connection.table_exists?('solid_queue_jobs')
      puts "\nSolidQueue Statistics:"
      puts "  Pending Jobs: #{SolidQueue::Job.pending.count}"
      puts "  Running Jobs: #{SolidQueue::Job.running.count}"
      puts "  Failed Jobs: #{SolidQueue::Job.failed.count}"
      puts "  Finished Jobs (last 24h): #{SolidQueue::Job.finished.where('finished_at > ?', 24.hours.ago).count}"
    end
    
    puts "\n" + "="*50
  end
  
  desc "Monitor memory usage over time"
  task monitor: :environment do
    puts "Starting memory monitoring (Ctrl+C to stop)..."
    puts "Time, Memory(MB), Objects, Threads"
    
    begin
      loop do
        memory_mb = `ps -o rss= -p #{Process.pid}`.to_i / 1024
        objects = ObjectSpace.count_objects[:TOTAL] if defined?(ObjectSpace)
        threads = Thread.list.count
        
        puts "#{Time.current.strftime('%H:%M:%S')}, #{memory_mb}, #{objects}, #{threads}"
        sleep 10
      end
    rescue Interrupt
      puts "\nMonitoring stopped."
    end
  end
  
  desc "Test memory usage of specific operations"
  task test: :environment do
    puts "\n=== Memory Usage Tests ==="
    
    # Test 1: Basic ActiveRecord queries
    puts "\nTest 1: ActiveRecord Queries"
    memory_before = `ps -o rss= -p #{Process.pid}`.to_i / 1024
    
    # Simulate typical queries
    User.limit(100).to_a if defined?(User)
    Business.limit(50).to_a if defined?(Business)
    
    memory_after = `ps -o rss= -p #{Process.pid}`.to_i / 1024
    puts "Memory before: #{memory_before}MB, after: #{memory_after}MB, diff: #{memory_after - memory_before}MB"
    
    # Test 2: Job execution simulation
    if defined?(AnalyticsProcessingJob)
      puts "\nTest 2: Analytics Job Simulation"
      memory_before = `ps -o rss= -p #{Process.pid}`.to_i / 1024
      
      # Don't actually run the job, just test object creation
      job = AnalyticsProcessingJob.new
      
      memory_after = `ps -o rss= -p #{Process.pid}`.to_i / 1024
      puts "Memory before: #{memory_before}MB, after: #{memory_after}MB, diff: #{memory_after - memory_before}MB"
    end
    
    # Force GC and check impact
    puts "\nGarbage Collection Impact:"
    memory_before_gc = `ps -o rss= -p #{Process.pid}`.to_i / 1024
    GC.start
    memory_after_gc = `ps -o rss= -p #{Process.pid}`.to_i / 1024
    puts "Memory before GC: #{memory_before_gc}MB, after GC: #{memory_after_gc}MB, freed: #{memory_before_gc - memory_after_gc}MB"
  end
  
  desc "Clean up old SolidQueue jobs to free memory"
  task cleanup_jobs: :environment do
    if defined?(SolidQueue)
      puts "Cleaning up old SolidQueue jobs..."
      
      # Delete finished jobs older than 7 days
      old_jobs = SolidQueue::Job.finished.where('finished_at < ?', 7.days.ago)
      count = old_jobs.count
      old_jobs.delete_all
      
      # Delete failed jobs older than 30 days
      old_failed = SolidQueue::Job.failed.where('created_at < ?', 30.days.ago)
      failed_count = old_failed.count
      old_failed.delete_all
      
      puts "Deleted #{count} finished jobs and #{failed_count} old failed jobs"
      
      # Force garbage collection
      GC.start
      puts "Triggered garbage collection"
    else
      puts "SolidQueue not available"
    end
  end
end 