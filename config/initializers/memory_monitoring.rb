# Memory monitoring and optimization for Render deployment
# frozen_string_literal: true

Rails.application.configure do
  if Rails.env.production?
    # Configure Ruby garbage collection for better memory management
    # Tune GC to be more aggressive about freeing memory
    
    # Set GC environment variables if not already set
    ENV['RUBY_GC_HEAP_INIT_SLOTS'] ||= '10000'        # Start with fewer slots
    ENV['RUBY_GC_HEAP_FREE_SLOTS'] ||= '3000'         # Keep fewer free slots
    ENV['RUBY_GC_HEAP_GROWTH_FACTOR'] ||= '1.25'      # Slower heap growth
    ENV['RUBY_GC_HEAP_GROWTH_MAX_SLOTS'] ||= '5000'   # Limit growth
    ENV['RUBY_GC_MALLOC_LIMIT'] ||= '16000000'        # 16MB malloc limit
    ENV['RUBY_GC_MALLOC_LIMIT_MAX'] ||= '32000000'    # 32MB malloc max
    ENV['RUBY_GC_MALLOC_LIMIT_GROWTH_FACTOR'] ||= '1.4'
    ENV['RUBY_GC_OLDMALLOC_LIMIT'] ||= '16000000'     # Old malloc limit
    ENV['RUBY_GC_OLDMALLOC_LIMIT_MAX'] ||= '32000000' # Old malloc max
    
    # Configure Rails to be more memory conscious
    config.cache_classes = true
    config.eager_load = true
    
    # Reduce Active Record connection checkout timeout
    config.active_record.connection_checkout_timeout = 2
    
    # Memory usage middleware for monitoring
    config.middleware.use Class.new do
      def initialize(app)
        @app = app
      end
      
      def call(env)
        # Check memory before request
        memory_before = memory_usage_mb
        
        response = @app.call(env)
        
        # Check memory after request
        memory_after = memory_usage_mb
        memory_diff = memory_after - memory_before
        
        # Log if memory usage is high or increased significantly
        if memory_after > 400 || memory_diff > 50
          Rails.logger.warn "High memory usage: #{memory_after}MB (diff: +#{memory_diff}MB) for #{env['REQUEST_METHOD']} #{env['PATH_INFO']}"
        end
        
        # Force GC if memory is getting high
        if memory_after > 450
          Rails.logger.info "Triggering GC due to high memory usage: #{memory_after}MB"
          GC.start
        end
        
        response
      end
      
      private
      
      def memory_usage_mb
        `ps -o rss= -p #{Process.pid}`.to_i / 1024
      end
    end
    
    # Add periodic memory reporting
    if defined?(Rails::Server)
      Thread.new do
        loop do
          sleep 60 # Check every minute
          memory_mb = `ps -o rss= -p #{Process.pid}`.to_i / 1024
          
          if memory_mb > 400
            Rails.logger.warn "Memory usage alert: #{memory_mb}MB - Triggering GC"
            GC.start
          else
            Rails.logger.info "Memory usage: #{memory_mb}MB"
          end
        rescue => e
          Rails.logger.error "Memory monitoring error: #{e.message}"
        end
      end
    end
  end
end

# Memory profiling utilities (only in development)
if Rails.env.development?
  class MemoryProfiler
    def self.profile(description = "Memory Profile")
      require 'benchmark'
      require 'objspace'
      
      ObjectSpace.count_objects_size # Force GC stats update
      
      puts "\n=== #{description} ==="
      puts "Memory before: #{memory_usage_mb}MB"
      puts "Objects before: #{ObjectSpace.count_objects[:TOTAL]}"
      
      result = nil
      time = Benchmark.realtime do
        result = yield
      end
      
      GC.start # Force GC to see actual memory impact
      
      puts "Memory after: #{memory_usage_mb}MB"
      puts "Objects after: #{ObjectSpace.count_objects[:TOTAL]}"
      puts "Time: #{time.round(2)}s"
      puts "========================\n"
      
      result
    end
    
    private
    
    def self.memory_usage_mb
      `ps -o rss= -p #{Process.pid}`.to_i / 1024
    end
  end
end 