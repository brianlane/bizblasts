# frozen_string_literal: true

# Base job class for all application background jobs
# Provides configuration for retries and error handling
class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError
  
  # Memory optimization for 512MB plan
  queue_as :default
  
  # Memory-efficient job execution wrapper
  around_perform do |job, block|
    memory_before = current_memory_mb if Rails.env.production?
    
    begin
      # Log job start with memory usage
      if Rails.env.production?
        Rails.logger.info "[Job Start] #{job.class.name} - Memory: #{memory_before}MB"
      end
      
      block.call
      
    ensure
      if Rails.env.production?
        memory_after = current_memory_mb
        memory_diff = memory_after - memory_before
        
        Rails.logger.info "[Job End] #{job.class.name} - Memory: #{memory_after}MB (#{memory_diff > 0 ? '+' : ''}#{memory_diff}MB)"
        
        # Force garbage collection for memory-intensive jobs
        if memory_diff > 50 || memory_after > 350
          Rails.logger.info "[Job GC] Triggering garbage collection after #{job.class.name}"
          GC.start(full_mark: false, immediate_sweep: true)
          final_memory = current_memory_mb
          Rails.logger.info "[Job GC] Final memory: #{final_memory}MB (freed #{memory_after - final_memory}MB)"
        end
      end
    end
  end
  
  private
  
  def current_memory_mb
    `ps -o rss= -p #{Process.pid}`.to_i / 1024
  end
  
  # Memory-efficient database query helper
  def find_in_batches_memory_safe(relation, batch_size: 100)
    relation.find_in_batches(batch_size: batch_size) do |batch|
      yield batch
      
      # Force garbage collection between batches for large datasets
      if Rails.env.production? && batch_size > 50
        GC.start(full_mark: false, immediate_sweep: false)
      end
    end
  end
  
  # Helper method to prevent memory leaks in loops
  def process_with_memory_management(items, chunk_size: 50)
    items.each_slice(chunk_size).with_index do |chunk, index|
      yield chunk
      
      # Trigger GC every 10 chunks in production
      if Rails.env.production? && (index + 1) % 10 == 0
        GC.start(full_mark: false, immediate_sweep: false)
      end
    end
  end
end
