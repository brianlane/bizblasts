# frozen_string_literal: true

namespace :memory do
  desc "Profile memory usage of the application"
  task profile: :environment do
    require 'objspace'
    
    puts "Memory Profiling Report"
    puts "======================"
    puts "Rails Environment: #{Rails.env}"
    puts "Ruby Version: #{RUBY_VERSION}"
    puts "Process ID: #{Process.pid}"
    puts
    
    # Get current memory usage
    memory_mb = `ps -o rss= -p #{Process.pid}`.to_i / 1024
    puts "Current Memory Usage: #{memory_mb}MB"
    puts
    
    # Ruby object space statistics
    puts "Ruby Object Space Statistics:"
    puts "============================="
    ObjectSpace.each_object.group_by(&:class).sort_by { |k, v| v.size }.reverse.first(20).each do |klass, objects|
      puts "#{klass}: #{objects.size} objects"
    end
    puts
    
    # Garbage collection statistics
    puts "Garbage Collection Statistics:"
    puts "=============================="
    gc_stats = GC.stat
    gc_stats.each do |key, value|
      puts "#{key}: #{value}"
    end
    puts
    
    # Memory usage by gem (if available)
    if defined?(ObjectSpace)
      puts "Memory Usage by Source Location (Top 20):"
      puts "=========================================="
      
      memory_by_location = Hash.new(0)
      ObjectSpace.each_object do |obj|
        next unless obj.respond_to?(:class)
        
        # Try to get source location
        if obj.respond_to?(:source_location) && obj.source_location
          location = obj.source_location[0]
          memory_by_location[location] += ObjectSpace.memsize_of(obj)
        end
      end
      
      memory_by_location.sort_by { |k, v| v }.reverse.first(20).each do |location, size|
        puts "#{location}: #{(size / 1024.0 / 1024.0).round(2)}MB"
      end
    end
    puts
    
    # Database connection pool status
    puts "Database Connection Pool Status:"
    puts "================================"
    ActiveRecord::Base.connection_pool.with_connection do |conn|
      pool = ActiveRecord::Base.connection_pool
      puts "Pool size: #{pool.size}"
      puts "Active connections: #{pool.connections.count(&:in_use?)}"
      puts "Available connections: #{pool.available_connection_count}"
    end
    puts
    
    # SolidQueue status (if available)
    if defined?(SolidQueue)
      puts "SolidQueue Status:"
      puts "=================="
      begin
        puts "Pending jobs: #{SolidQueue::Job.pending.count}"
        puts "Failed jobs: #{SolidQueue::Job.failed.count}"
        puts "Running jobs: #{SolidQueue::Job.running.count}"
      rescue => e
        puts "Error getting SolidQueue status: #{e.message}"
      end
    end
    puts
    
    puts "Memory profiling complete!"
  end
  
  desc "Monitor memory usage over time"
  task monitor: :environment do
    puts "Starting memory monitoring (Ctrl+C to stop)..."
    puts "Time\t\tMemory (MB)\tGC Count\tObjects"
    puts "=" * 60
    
    trap("INT") { puts "\nMonitoring stopped."; exit }
    
    loop do
      memory_mb = `ps -o rss= -p #{Process.pid}`.to_i / 1024
      gc_count = GC.count
      object_count = ObjectSpace.each_object.count
      
      puts "#{Time.current.strftime('%H:%M:%S')}\t#{memory_mb}\t\t#{gc_count}\t\t#{object_count}"
      
      sleep 5
    end
  end
  
  desc "Test memory usage of background jobs"
  task test_jobs: :environment do
    puts "Testing memory usage of background jobs..."
    puts "=========================================="
    
    # Test each job type
    job_classes = [
      'AnalyticsProcessingJob',
      'SendPaymentRemindersJob',
      'AutoCancelUnpaidProductOrdersJob',
      'MarketingCampaignJob'
    ]
    
    job_classes.each do |job_class_name|
      next unless Object.const_defined?(job_class_name)
      
      job_class = Object.const_get(job_class_name)
      
      puts "\nTesting #{job_class_name}:"
      puts "-" * 30
      
      memory_before = `ps -o rss= -p #{Process.pid}`.to_i / 1024
      gc_before = GC.count
      
      begin
        # Perform a test job (you may need to adjust parameters)
        case job_class_name
        when 'AnalyticsProcessingJob'
          job_class.perform_now('booking_summary', nil, { start_date: 1.week.ago.to_date, end_date: Date.today })
        when 'SendPaymentRemindersJob'
          job_class.perform_now
        when 'AutoCancelUnpaidProductOrdersJob'
          job_class.perform_now
        when 'MarketingCampaignJob'
          # Skip if no campaigns exist
          next unless MarketingCampaign.exists?
          campaign = MarketingCampaign.first
          job_class.perform_now(campaign.id, 'test')
        end
        
        memory_after = `ps -o rss= -p #{Process.pid}`.to_i / 1024
        gc_after = GC.count
        
        puts "Memory before: #{memory_before}MB"
        puts "Memory after: #{memory_after}MB"
        puts "Memory difference: #{memory_after - memory_before}MB"
        puts "GC runs: #{gc_after - gc_before}"
        
      rescue => e
        puts "Error testing #{job_class_name}: #{e.message}"
      end
    end
    
    puts "\nJob memory testing complete!"
  end
  
  desc "Force garbage collection and report memory freed"
  task gc: :environment do
    puts "Forcing garbage collection..."
    
    memory_before = `ps -o rss= -p #{Process.pid}`.to_i / 1024
    objects_before = ObjectSpace.each_object.count
    
    puts "Memory before GC: #{memory_before}MB"
    puts "Objects before GC: #{objects_before}"
    
    # Force full garbage collection
    GC.start(full_mark: true, immediate_sweep: true)
    
    memory_after = `ps -o rss= -p #{Process.pid}`.to_i / 1024
    objects_after = ObjectSpace.each_object.count
    
    puts "Memory after GC: #{memory_after}MB"
    puts "Objects after GC: #{objects_after}"
    puts "Memory freed: #{memory_before - memory_after}MB"
    puts "Objects freed: #{objects_before - objects_after}"
  end
end 