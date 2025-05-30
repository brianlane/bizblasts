class AnalyticsProcessingJob < ApplicationJob
  queue_as :analytics
  
  # Add job timeout and retry settings for memory safety
  retry_on StandardError, wait: :exponentially_longer, attempts: 3
  discard_on ActiveJob::DeserializationError
  
  # Add memory monitoring
  before_perform :log_memory_usage
  after_perform :log_memory_usage_and_gc

  def perform(report_type, tenant_id = nil, options = {})
    business = nil # Define business outside the if block
    # Set up tenant context if provided
    if tenant_id.present?
      business = Business.find_by(id: tenant_id)
      return unless business
      
      # Use ActsAsTenant API to set the current tenant
      ActsAsTenant.current_tenant = business
    end
    
    # Default date range if not provided - limit to smaller ranges for memory
    options[:start_date] ||= 7.days.ago.to_date # Reduced from 30 days
    options[:end_date] ||= Date.today
    
    # Add memory limit check
    if memory_usage_mb > 400 # MB threshold for Render free tier
      Rails.logger.warn "Memory usage high (#{memory_usage_mb}MB), skipping analytics job"
      return
    end
    
    # Process the report and store result explicitly
    report_result = 
      case report_type
      when 'booking_summary'
        process_booking_summary(options)
      when 'revenue_summary'
        process_revenue_summary(options)
      when 'marketing_summary'
        process_marketing_summary(options)
      when 'customer_retention'
        process_customer_retention(options)
      when 'staff_performance'
        process_staff_performance(options)
      else
        Rails.logger.error "Unknown report type: #{report_type}"
        nil # Ensure nil is returned for unknown types
      end
    
    return report_result # Explicitly return the result

  ensure # Use ensure block to guarantee reset
    # Reset tenant context using ActsAsTenant API if it was set
    ActsAsTenant.current_tenant = nil if tenant_id.present?
    # Force garbage collection to free memory
    GC.start if Rails.env.production?
  end
  
  private
  
  def log_memory_usage
    Rails.logger.info "Job #{self.class.name} - Memory usage: #{memory_usage_mb}MB"
  end
  
  def log_memory_usage_and_gc
    Rails.logger.info "Job #{self.class.name} completed - Memory usage: #{memory_usage_mb}MB"
    GC.start if Rails.env.production?
  end
  
  def memory_usage_mb
    `ps -o rss= -p #{Process.pid}`.to_i / 1024
  end
  
  def process_booking_summary(options)
    # Calculate booking statistics with batching to reduce memory usage
    start_date = options[:start_date]
    end_date = options[:end_date]
    
    # Use find_each for memory-efficient batch processing
    bookings = Booking.where(created_at: start_date..end_date)
    
    summary = {
      total_bookings: 0,
      completed_bookings: 0,
      cancelled_bookings: 0,
      total_revenue: 0
    }
    
    # Process in batches to avoid loading all records into memory
    bookings.find_each(batch_size: 100) do |booking|
      summary[:total_bookings] += 1
      
      case booking.status
      when 'completed'
        summary[:completed_bookings] += 1
        summary[:total_revenue] += booking.total_amount || 0
      when 'cancelled'
        summary[:cancelled_bookings] += 1
      end
      
      # Trigger GC periodically during large operations
      GC.start if summary[:total_bookings] % 500 == 0
    end
    
    summary
  end
  
  def process_revenue_summary(options)
    # Calculate revenue statistics
    start_date = options[:start_date]
    end_date = options[:end_date]
    
    # Get all successful payments in the date range
    payments = Payment.successful.where('created_at BETWEEN ? AND ?', start_date.beginning_of_day, end_date.end_of_day)
    
    # Calculate metrics
    total_revenue = payments.sum(:amount).to_f
    payment_count = payments.count
    
    # Break down by payment method
    by_method = payments.group(:payment_method).sum(:amount)
    
    # Store results
    result = {
      period: "#{start_date} to #{end_date}",
      total_revenue: total_revenue,
      payment_count: payment_count,
      average_payment: payment_count > 0 ? (total_revenue / payment_count).round(2) : 0,
      by_payment_method: by_method,
      generated_at: Time.current
    }
    
    Rails.logger.info "Revenue Summary Report: #{result.inspect}"
    
    # Return the result
    result
  end
  
  def process_marketing_summary(options)
    # Simplified placeholder implementation
    campaigns = MarketingCampaign.where('created_at BETWEEN ? AND ?', options[:start_date].beginning_of_day, options[:end_date].end_of_day)
    
    result = {
      period: "#{options[:start_date]} to #{options[:end_date]}",
      total_campaigns: campaigns.count,
      completed_campaigns: campaigns.completed.count,
      email_campaigns: campaigns.where(campaign_type: :email).count,
      sms_campaigns: campaigns.where(campaign_type: :sms).count,
      combined_campaigns: campaigns.where(campaign_type: :combined).count,
      generated_at: Time.current
    }
    
    Rails.logger.info "Marketing Summary Report: #{result.inspect}"
    
    # Return the result
    result
  end
  
  def process_customer_retention(options)
    # Simplified placeholder implementation
    result = {
      period: "#{options[:start_date]} to #{options[:end_date]}",
      customer_count: Customer.count,
      new_customers: Customer.where('created_at BETWEEN ? AND ?', options[:start_date].beginning_of_day, options[:end_date].end_of_day).count,
      active_customers: Customer.active.count,
      repeat_customers_count: 0, # This would require more complex logic
      generated_at: Time.current
    }
    
    Rails.logger.info "Customer Retention Report: #{result.inspect}"
    
    # Return the result
    result
  end
  
  def process_staff_performance(options)
    # Simplified placeholder implementation
    staff_members = StaffMember.active
    
    # Create staff performance data
    staff_data = staff_members.map do |staff|
      bookings = Booking.where(bookable: staff)
                        .where('start_time BETWEEN ? AND ?', options[:start_date].beginning_of_day, options[:end_date].end_of_day)
      
      {
        staff_id: staff.id,
        staff_name: staff.name,
        total_bookings: bookings.count,
        completed_bookings: bookings.completed.count,
        cancelled_bookings: bookings.cancelled.count,
        no_show_bookings: bookings.no_show.count,
        completion_rate: bookings.any? ? (bookings.completed.count.to_f / bookings.count * 100).round(2) : 0
      }
    end
    
    result = {
      period: "#{options[:start_date]} to #{options[:end_date]}",
      staff_count: staff_members.count,
      staff_performance: staff_data,
      generated_at: Time.current
    }
    
    Rails.logger.info "Staff Performance Report: #{result.inspect}"
    
    # Return the result
    result
  end
end
