class AnalyticsProcessingJob < ApplicationJob
  queue_as :analytics

  def perform(report_type, tenant_id = nil, options = {})
    # Set up tenant context if provided
    if tenant_id.present?
      business = Business.find_by(id: tenant_id)
      return unless business
      
      # Set the current tenant for the duration of this job
      Current.business = business
      Current.business_id = business.id
    end
    
    # Default date range if not provided
    options[:start_date] ||= 30.days.ago.to_date
    options[:end_date] ||= Date.current
    
    # Process the report based on its type
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
    end
    
    # Reset tenant context when done
    Current.reset if tenant_id.present?
  end
  
  private
  
  def process_booking_summary(options)
    # Calculate booking statistics
    start_date = options[:start_date]
    end_date = options[:end_date]
    
    # Get all bookings in the date range
    bookings = Booking.where('start_time BETWEEN ? AND ?', start_date.beginning_of_day, end_date.end_of_day)
    
    # Calculate metrics
    total_count = bookings.count
    completed_count = bookings.completed.count
    cancelled_count = bookings.cancelled.count
    no_show_count = bookings.no_show.count
    
    completion_rate = total_count > 0 ? (completed_count.to_f / total_count * 100).round(2) : 0
    cancellation_rate = total_count > 0 ? (cancelled_count.to_f / total_count * 100).round(2) : 0
    
    # Calculate average booking value
    completed_with_amount = bookings.completed.where.not(amount: nil)
    average_value = completed_with_amount.any? ? completed_with_amount.average(:amount).to_f.round(2) : 0
    
    # Store results
    result = {
      period: "#{start_date} to #{end_date}",
      total_bookings: total_count,
      completed_bookings: completed_count,
      cancelled_bookings: cancelled_count,
      no_show_bookings: no_show_count,
      completion_rate: completion_rate,
      cancellation_rate: cancellation_rate,
      average_booking_value: average_value,
      generated_at: Time.current
    }
    
    # In a real implementation, this might be stored in a database or sent via email
    Rails.logger.info "Booking Summary Report: #{result.inspect}"
    
    # Return the result
    result
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
