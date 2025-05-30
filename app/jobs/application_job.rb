# frozen_string_literal: true

# Base job class for all application background jobs
# Provides configuration for retries, error handling, and memory optimization
class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  retry_on ActiveRecord::Deadlocked, wait: :exponentially_longer, attempts: 3
  
  # Most jobs are safe to ignore if the underlying records are no longer available
  discard_on ActiveJob::DeserializationError
  
  # Memory optimization: Discard jobs that cause out of memory errors
  discard_on NoMemoryError, StandardError do |job, error|
    if error.message.include?('memory') || error.message.include?('Memory')
      Rails.logger.error "Job #{job.class.name} discarded due to memory error: #{error.message}"
      true
    else
      false
    end
  end
  
  # Queue configuration for memory efficiency
  queue_with_priority 0  # Default priority
  
  # Add memory monitoring to all jobs
  around_perform do |job, block|
    memory_before = memory_usage_mb if Rails.env.production?
    
    # Set job timeout to prevent runaway processes
    Timeout.timeout(job_timeout) do
      block.call
    end
    
    if Rails.env.production?
      memory_after = memory_usage_mb
      memory_diff = memory_after - memory_before
      
      # Log memory usage for monitoring
      Rails.logger.info "Job #{job.class.name} completed - Memory: #{memory_after}MB (#{memory_diff >= 0 ? '+' : ''}#{memory_diff}MB)"
      
      # Force GC if job used significant memory
      if memory_diff > 50 || memory_after > 400
        Rails.logger.info "Triggering GC after #{job.class.name} - High memory usage"
        GC.start
      end
    end
  rescue Timeout::Error
    Rails.logger.error "Job #{job.class.name} timed out after #{job_timeout} seconds"
    raise
  end
  
  private
  
  def memory_usage_mb
    `ps -o rss= -p #{Process.pid}`.to_i / 1024
  end
  
  def job_timeout
    # Default timeout of 5 minutes, can be overridden in subclasses
    300
  end
end
