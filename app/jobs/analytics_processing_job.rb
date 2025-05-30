class AnalyticsProcessingJob < ApplicationJob
  queue_as :analytics

  def perform(report_type, tenant_id = nil, options = {})
    business = nil # Define business outside the if block
    # Set up tenant context if provided
    if tenant_id.present?
      business = Business.find_by(id: tenant_id)
      return unless business
      
      # Use ActsAsTenant API to set the current tenant
      ActsAsTenant.current_tenant = business
    end
    
    # Default date range if not provided
    options[:start_date] ||= 30.days.ago.to_date
    options[:end_date] ||= Date.today
    
    # Process the report and store result explicitly with memory management
    report_result = 
      case report_type
      when 'booking_summary'
        process_booking_summary_memory_safe(options)
      when 'revenue_summary'
        process_revenue_summary_memory_safe(options)
      when 'marketing_summary'
        process_marketing_summary_memory_safe(options)
      when 'customer_retention'
        process_customer_retention_memory_safe(options)
      when 'staff_performance'
        process_staff_performance_memory_safe(options)
      else
        Rails.logger.error "Unknown report type: #{report_type}"
        nil # Ensure nil is returned for unknown types
      end
    
    return report_result # Explicitly return the result

  ensure # Use ensure block to guarantee reset
    # Reset tenant context using ActsAsTenant API if it was set
    ActsAsTenant.current_tenant = nil if tenant_id.present?
  end
  
  private
  
  # Memory-optimized booking summary processing
  def process_booking_summary_memory_safe(options)
    start_date = options[:start_date]
    end_date = options[:end_date]
    
    # Use memory-safe batch processing for large datasets
    total_bookings = 0
    confirmed_bookings = 0
    cancelled_bookings = 0
    pending_bookings = 0
    
    # Process bookings in batches to prevent memory spikes
    find_in_batches_memory_safe(
      Booking.where('created_at BETWEEN ? AND ?', start_date.beginning_of_day, end_date.end_of_day),
      batch_size: 100
    ) do |batch|
      total_bookings += batch.size
      confirmed_bookings += batch.count { |b| b.status == 'confirmed' }
      cancelled_bookings += batch.count { |b| b.status == 'cancelled' }
      pending_bookings += batch.count { |b| b.status == 'pending' }
    end
    
    # Calculate average booking value in batches
    total_value = 0.0
    value_count = 0
    
    find_in_batches_memory_safe(
      Booking.confirmed.where('created_at BETWEEN ? AND ?', start_date.beginning_of_day, end_date.end_of_day),
      batch_size: 100
    ) do |batch|
      batch_values = batch.map(&:total_amount).compact
      total_value += batch_values.sum
      value_count += batch_values.size
    end
    
    result = {
      period: "#{start_date} to #{end_date}",
      total_bookings: total_bookings,
      confirmed_bookings: confirmed_bookings,
      cancelled_bookings: cancelled_bookings,
      pending_bookings: pending_bookings,
      average_booking_value: value_count > 0 ? (total_value / value_count).round(2) : 0,
      generated_at: Time.current
    }
    
    Rails.logger.info "Booking Summary Report: #{result.inspect}"
    result
  end
  
  # Memory-optimized revenue summary processing
  def process_revenue_summary_memory_safe(options)
    start_date = options[:start_date]
    end_date = options[:end_date]
    
    # Process payments in batches to avoid loading all into memory
    total_revenue = 0.0
    payment_count = 0
    method_totals = Hash.new(0.0)
    
    find_in_batches_memory_safe(
      Payment.successful.where('created_at BETWEEN ? AND ?', start_date.beginning_of_day, end_date.end_of_day),
      batch_size: 100
    ) do |batch|
      payment_count += batch.size
      batch.each do |payment|
        amount = payment.amount.to_f
        total_revenue += amount
        method_totals[payment.payment_method] += amount
      end
    end
    
    result = {
      period: "#{start_date} to #{end_date}",
      total_revenue: total_revenue,
      payment_count: payment_count,
      average_payment: payment_count > 0 ? (total_revenue / payment_count).round(2) : 0,
      by_payment_method: method_totals,
      generated_at: Time.current
    }
    
    Rails.logger.info "Revenue Summary Report: #{result.inspect}"
    result
  end
  
  # Memory-optimized marketing summary processing
  def process_marketing_summary_memory_safe(options)
    # Use efficient counting queries instead of loading records
    date_range = options[:start_date].beginning_of_day..options[:end_date].end_of_day
    
    result = {
      period: "#{options[:start_date]} to #{options[:end_date]}",
      total_campaigns: MarketingCampaign.where(created_at: date_range).count,
      completed_campaigns: MarketingCampaign.where(created_at: date_range).completed.count,
      email_campaigns: MarketingCampaign.where(created_at: date_range, campaign_type: :email).count,
      sms_campaigns: MarketingCampaign.where(created_at: date_range, campaign_type: :sms).count,
      combined_campaigns: MarketingCampaign.where(created_at: date_range, campaign_type: :combined).count,
      generated_at: Time.current
    }
    
    Rails.logger.info "Marketing Summary Report: #{result.inspect}"
    result
  end
  
  # Memory-optimized customer retention processing
  def process_customer_retention_memory_safe(options)
    date_range = options[:start_date].beginning_of_day..options[:end_date].end_of_day
    
    # Use efficient counting queries
    result = {
      period: "#{options[:start_date]} to #{options[:end_date]}",
      customer_count: Customer.count,
      new_customers: Customer.where(created_at: date_range).count,
      active_customers: Customer.active.count,
      repeat_customers_count: 0, # This would require more complex logic
      generated_at: Time.current
    }
    
    Rails.logger.info "Customer Retention Report: #{result.inspect}"
    result
  end
  
  # Memory-optimized staff performance processing
  def process_staff_performance_memory_safe(options)
    date_range = options[:start_date].beginning_of_day..options[:end_date].end_of_day
    
    # Use efficient queries instead of loading all staff records
    result = {
      period: "#{options[:start_date]} to #{options[:end_date]}",
      total_staff: StaffMember.active.count,
      bookings_handled: Booking.where(created_at: date_range).joins(:staff_member).count,
      generated_at: Time.current
    }
    
    Rails.logger.info "Staff Performance Report: #{result.inspect}"
    result
  end
end
