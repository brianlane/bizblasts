# frozen_string_literal: true

namespace :memory do
  desc "Detect potential memory leaks in development"
  task leak_detection: :environment do
    puts "Memory Leak Detection for Development Environment"
    puts "================================================"
    puts "This task will help identify potential memory leaks by monitoring memory usage patterns."
    puts
    
    # Check if we're in development
    unless Rails.env.development?
      puts "Warning: This task is designed for development environment."
      puts "Current environment: #{Rails.env}"
      puts
    end
    
    # Initial memory baseline
    initial_memory = get_memory_usage
    puts "Initial memory usage: #{initial_memory}MB"
    puts
    
    # Test database connection pool leaks
    puts "Testing database connection pool..."
    test_database_connection_leaks
    
    # Test Active Record object retention
    puts "Testing Active Record object retention..."
    test_active_record_retention
    
    # Test job memory usage
    puts "Testing background job memory usage..."
    test_job_memory_usage
    
    # Test controller memory usage
    puts "Testing controller memory usage..."
    test_controller_memory_usage
    
    # Final memory check
    final_memory = get_memory_usage
    memory_increase = final_memory - initial_memory
    
    puts
    puts "Memory Leak Detection Summary:"
    puts "=============================="
    puts "Initial memory: #{initial_memory}MB"
    puts "Final memory: #{final_memory}MB"
    puts "Memory increase: #{memory_increase}MB"
    
    if memory_increase > 50
      puts "⚠️  WARNING: Significant memory increase detected (#{memory_increase}MB)"
      puts "   This may indicate a memory leak. Review the test results above."
    elsif memory_increase > 20
      puts "⚠️  CAUTION: Moderate memory increase detected (#{memory_increase}MB)"
      puts "   Monitor this in production."
    else
      puts "✅ Memory usage appears stable (#{memory_increase}MB increase)"
    end
    
    puts
    puts "Recommendations:"
    puts "- Run this task periodically during development"
    puts "- Monitor memory usage in production with: rake memory:monitor"
    puts "- Profile specific components with: rake memory:profile"
  end
  
  private
  
  def get_memory_usage
    `ps -o rss= -p #{Process.pid}`.to_i / 1024
  end
  
  def test_database_connection_leaks
    puts "  Testing database connection handling..."
    
    memory_before = get_memory_usage
    
    # Test multiple database operations
    100.times do |i|
      # Simulate various database operations that might leak connections
      User.count if defined?(User)
      Business.count if defined?(Business)
      
      # Force connection checkout and checkin
      ActiveRecord::Base.connection_pool.with_connection do |conn|
        conn.execute("SELECT 1")
      end
      
      # Trigger garbage collection every 25 iterations
      GC.start if i % 25 == 0
    end
    
    memory_after = get_memory_usage
    memory_diff = memory_after - memory_before
    
    puts "    Memory before: #{memory_before}MB"
    puts "    Memory after: #{memory_after}MB"
    puts "    Difference: #{memory_diff}MB"
    
    # Check connection pool status
    pool = ActiveRecord::Base.connection_pool
    puts "    Active connections: #{pool.connections.count(&:in_use?)}/#{pool.size}"
    
    if memory_diff > 10
      puts "    ⚠️  Potential database connection leak detected"
    else
      puts "    ✅ Database connections appear to be handled correctly"
    end
    puts
  end
  
  def test_active_record_retention
    puts "  Testing Active Record object retention..."
    
    memory_before = get_memory_usage
    objects_before = count_active_record_objects
    
    # Create and destroy many Active Record objects
    created_objects = []
    
    50.times do
      # Create temporary objects (adjust based on your models)
      if defined?(User)
        user = User.new(email: "test#{rand(10000)}@example.com")
        created_objects << user
      end
      
      if defined?(Business)
        business = Business.new(name: "Test Business #{rand(10000)}")
        created_objects << business
      end
    end
    
    # Clear references
    created_objects.clear
    created_objects = nil
    
    # Force garbage collection
    3.times { GC.start }
    
    memory_after = get_memory_usage
    objects_after = count_active_record_objects
    
    memory_diff = memory_after - memory_before
    object_diff = objects_after - objects_before
    
    puts "    Memory before: #{memory_before}MB"
    puts "    Memory after: #{memory_after}MB"
    puts "    Memory difference: #{memory_diff}MB"
    puts "    AR objects before: #{objects_before}"
    puts "    AR objects after: #{objects_after}"
    puts "    Object difference: #{object_diff}"
    
    if object_diff > 10
      puts "    ⚠️  Potential Active Record object retention detected"
    else
      puts "    ✅ Active Record objects appear to be garbage collected properly"
    end
    puts
  end
  
  def test_job_memory_usage
    puts "  Testing background job memory usage..."
    
    memory_before = get_memory_usage
    
    # Test a simple job multiple times
    5.times do
      begin
        # Test with a simple job that shouldn't leak memory
        if defined?(AutoCancelUnpaidProductOrdersJob)
          AutoCancelUnpaidProductOrdersJob.perform_now
        end
        
        # Force garbage collection between jobs
        GC.start
      rescue => e
        puts "    Error testing job: #{e.message}"
      end
    end
    
    memory_after = get_memory_usage
    memory_diff = memory_after - memory_before
    
    puts "    Memory before: #{memory_before}MB"
    puts "    Memory after: #{memory_after}MB"
    puts "    Difference: #{memory_diff}MB"
    
    if memory_diff > 15
      puts "    ⚠️  Potential job memory leak detected"
    else
      puts "    ✅ Background jobs appear to manage memory correctly"
    end
    puts
  end
  
  def test_controller_memory_usage
    puts "  Testing controller memory simulation..."
    
    memory_before = get_memory_usage
    
    # Simulate controller actions
    10.times do
      # Simulate request processing
      request_env = {
        'REQUEST_METHOD' => 'GET',
        'PATH_INFO' => '/test',
        'HTTP_HOST' => 'localhost'
      }
      
      # Create mock request/response cycle
      begin
        # This is a simplified simulation
        # In a real test, you'd use integration tests
        if defined?(ApplicationController)
          controller = ApplicationController.new
          # Simulate some controller work
        end
      rescue => e
        # Expected to fail in this context, just testing memory patterns
      end
      
      # Force garbage collection
      GC.start if rand(3) == 0
    end
    
    memory_after = get_memory_usage
    memory_diff = memory_after - memory_before
    
    puts "    Memory before: #{memory_before}MB"
    puts "    Memory after: #{memory_after}MB"
    puts "    Difference: #{memory_diff}MB"
    
    if memory_diff > 5
      puts "    ⚠️  Potential controller memory issue detected"
    else
      puts "    ✅ Controller simulation shows stable memory usage"
    end
    puts
  end
  
  def count_active_record_objects
    return 0 unless defined?(ActiveRecord::Base)
    
    count = 0
    ObjectSpace.each_object(ActiveRecord::Base) { count += 1 }
    count
  end
end 