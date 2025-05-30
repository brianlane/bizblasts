# frozen_string_literal: true

# Memory optimization for Render 512MB plan
if Rails.env.production?
  # Ruby garbage collection optimization for low-memory environments
  # These settings are tuned for 512MB memory limit
  
  # More aggressive garbage collection
  GC::OPTS.merge!({
    # Reduce heap growth to prevent memory spikes
    RUBY_GC_HEAP_GROWTH_FACTOR: 1.1,       # Default 1.8, reduced for memory efficiency
    RUBY_GC_HEAP_GROWTH_MAX_SLOTS: 50000,  # Default unlimited, limit to prevent spikes
    
    # More frequent garbage collection
    RUBY_GC_MALLOC_LIMIT: 32 * 1024 * 1024,      # 32MB, default 16MB
    RUBY_GC_MALLOC_LIMIT_MAX: 64 * 1024 * 1024,  # 64MB, default 32MB
    RUBY_GC_MALLOC_LIMIT_GROWTH_FACTOR: 1.1,     # Default 1.4, reduced
    
    # Optimize heap slots
    RUBY_GC_HEAP_INIT_SLOTS: 20000,         # Start with fewer slots
    RUBY_GC_HEAP_FREE_SLOTS: 8000,          # Keep fewer free slots
    RUBY_GC_HEAP_OLDOBJECT_LIMIT_FACTOR: 0.9 # Default 1.0, more aggressive old object collection
  })
  
  # Apply the settings
  GC::OPTS.each do |key, value|
    ENV[key.to_s] = value.to_s
  end
  
  # Force immediate garbage collection on startup
  GC.start(full_mark: true, immediate_sweep: true)
  
  # Memory monitoring class
  class MemoryMonitor
    class << self
      def log_memory_usage(context = "Unknown")
        return unless Rails.env.production?
        
        memory_mb = current_memory_mb
        log_level = memory_mb > 400 ? :warn : :info
        
        Rails.logger.send(log_level, "[Memory] #{context}: #{memory_mb}MB (#{memory_percentage}%)")
        
        # Alert if memory usage is high
        if memory_mb > 450
          Rails.logger.error "[Memory Alert] High memory usage: #{memory_mb}MB - consider restarting"
        end
        
        memory_mb
      end
      
      def current_memory_mb
        `ps -o rss= -p #{Process.pid}`.to_i / 1024
      end
      
      def memory_percentage
        ((current_memory_mb / 512.0) * 100).round(1)
      end
      
      def trigger_gc_if_needed
        memory_mb = current_memory_mb
        if memory_mb > 350 # If using more than 350MB, trigger GC
          Rails.logger.info "[Memory] Triggering GC at #{memory_mb}MB"
          GC.start(full_mark: false, immediate_sweep: true)
          new_memory = current_memory_mb
          Rails.logger.info "[Memory] After GC: #{new_memory}MB (freed #{memory_mb - new_memory}MB)"
        end
      end
    end
  end
  
  # Setup memory monitoring hooks
  ActiveSupport::Notifications.subscribe 'start_processing.action_controller' do |name, started, finished, unique_id, data|
    MemoryMonitor.trigger_gc_if_needed if rand(100) < 5 # 5% chance to check
  end
  
  # Log memory usage every 100 requests
  class MemoryMiddleware
    def initialize(app)
      @app = app
      @request_count = 0
    end
    
    def call(env)
      @request_count += 1
      
      if @request_count % 100 == 0
        MemoryMonitor.log_memory_usage("After #{@request_count} requests")
      end
      
      @app.call(env)
    end
  end
  
  Rails.application.config.middleware.use MemoryMiddleware
  
  # Periodic memory cleanup (every 10 minutes)
  Thread.new do
    loop do
      sleep 600 # 10 minutes
      begin
        MemoryMonitor.log_memory_usage("Periodic check")
        MemoryMonitor.trigger_gc_if_needed
      rescue => e
        Rails.logger.error "[Memory] Error in periodic cleanup: #{e.message}"
      end
    end
  end if defined?(Thread)
end 