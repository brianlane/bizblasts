# frozen_string_literal: true

# Configure SolidQueue for memory optimization on Render
if defined?(SolidQueue)
  Rails.application.config.to_prepare do
    # Skip SolidQueue setup during asset compilation or when explicitly disabled
    next if ENV['RAILS_DISABLE_ASSET_COMPILATION'] == 'true'
    next if ENV['SKIP_SOLID_QUEUE_SETUP'] == 'true'
    next if Rails.env.test? && ENV['CI'].present? && ENV['RAILS_ENV'] != 'test'
    
    # Only proceed if we can actually connect to the database
    begin
      # Test database connection without triggering full schema load
      ActiveRecord::Base.connection.execute('SELECT 1')
      
      # Check if the solid_queue_recurring_tasks table exists
      unless ActiveRecord::Base.connection.table_exists?('solid_queue_recurring_tasks')
        Rails.logger.info "SolidQueue tables not found, skipping recurring task setup"
        next
      end
      
      Rails.application.config.active_job.queue_adapter = :solid_queue

      # Memory-optimized SolidQueue configuration
      SolidQueue.configure do |config|
        # Reduce worker threads for memory efficiency
        config.default_concurrency = ENV.fetch('SOLID_QUEUE_CONCURRENCY', 2).to_i
        
        # Optimize polling to reduce database load
        config.polling_interval = ENV.fetch('SOLID_QUEUE_POLLING_INTERVAL', 5).to_i
        
        # Set maximum number of threads per process
        config.max_number_of_threads = ENV.fetch('SOLID_QUEUE_MAX_THREADS', 5).to_i
        
        # Configure queues with different concurrency levels
        config.queues = {
          'default' => { threads: 1, processes: 1 },
          'analytics' => { threads: 1, processes: 1 }, # Heavy jobs get single thread
          'mailers' => { threads: 2, processes: 1 },   # Light jobs can have more
          'low_priority' => { threads: 1, processes: 1 }
        }
        
        # Enable job timeout to prevent runaway processes
        config.job_timeout = ENV.fetch('SOLID_QUEUE_JOB_TIMEOUT', 300).to_i # 5 minutes
        
        # Configure recurring task cleanup
        config.clear_finished_jobs_after = ENV.fetch('SOLID_QUEUE_CLEAR_JOBS_AFTER', 7.days).to_i
        
        # Optimize database connection settings for queue workers
        config.connects_to = {
          database: { 
            writing: :queue,
            # Use smaller connection pool for queue workers
            pool_size: ENV.fetch('SOLID_QUEUE_POOL_SIZE', 3).to_i
          }
        }
      end

      # Schedule auto-cancel of unpaid product orders every 15 minutes
      SolidQueue::RecurringTask.find_or_create_by!(key: 'auto_cancel_unpaid_product_orders') do |task|
        task.schedule    = '*/15 * * * *' # every 15 minutes
        task.class_name  = 'AutoCancelUnpaidProductOrdersJob'
        task.arguments   = '[]'
        task.queue_name  = 'low_priority' # Move to low priority queue
        task.priority    = 10 # Lower priority
        task.static      = true
        task.description = 'Auto cancel unpaid product orders after tier-specific deadlines'
      end
      
      # Configure garbage collection for better memory management
      if Rails.env.production?
        # Force garbage collection after each job to reclaim memory
        ActiveJob::Base.class_eval do
          around_perform do |job, block|
            block.call
            GC.start
          end
        end
      end
      
      Rails.logger.info "SolidQueue configured with memory optimizations - Concurrency: #{SolidQueue.config.default_concurrency}, Polling: #{SolidQueue.config.polling_interval}s"
      
    rescue ActiveRecord::ConnectionNotEstablished, ActiveRecord::NoDatabaseError, PG::ConnectionBad => e
      Rails.logger.info "Database not available for SolidQueue setup: #{e.message}"
      # Don't fail the application startup, just skip SolidQueue setup
    rescue ActiveRecord::StatementInvalid => e
      Rails.logger.info "Database schema not ready for SolidQueue: #{e.message}"
      # Table might not exist yet, skip setup
    rescue => e
      Rails.logger.warn "Unexpected error during SolidQueue setup: #{e.message}"
      # Log but don't fail
    end
  end
end
