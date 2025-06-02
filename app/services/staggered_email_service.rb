# frozen_string_literal: true

# Service to handle staggered email delivery to avoid rate limits
# Resend has a 2 requests/second limit, so we stagger emails accordingly
class StaggeredEmailService
  # Send multiple email specifications with staggered timing to respect rate limits
  def self.deliver_specifications(email_specifications, delay_between_emails: 1.second)
    return if email_specifications.empty?
    
    Rails.logger.info "[StaggeredEmail] Processing #{email_specifications.count} email specifications with #{delay_between_emails} delay"
    
    successful_deliveries = 0
    
    email_specifications.each_with_index do |spec, index|
      # First email sends immediately, subsequent emails are delayed
      delay = index * delay_between_emails
      
      success = if delay == 0
        spec.execute
      else
        spec.execute_with_delay(wait: delay)
      end
      
      if success
        successful_deliveries += 1
        Rails.logger.info "[StaggeredEmail] Email #{index + 1}/#{email_specifications.count} scheduled successfully"
      else
        Rails.logger.warn "[StaggeredEmail] Email #{index + 1}/#{email_specifications.count} skipped or failed"
      end
    end
    
    Rails.logger.info "[StaggeredEmail] Successfully scheduled #{successful_deliveries}/#{email_specifications.count} emails"
    successful_deliveries
  end

  # Legacy method for backward compatibility with existing mailer objects
  # DEPRECATED: Use deliver_specifications instead
  def self.deliver_multiple(email_jobs, delay_between_emails: 1.second)
    Rails.logger.warn "[StaggeredEmail] deliver_multiple is deprecated, use deliver_specifications instead"
    
    # Filter out nil email jobs (mailers that returned early due to conditions)
    valid_emails = email_jobs.compact
    return if valid_emails.empty?
    
    Rails.logger.info "[StaggeredEmail] Scheduling #{valid_emails.count} emails with #{delay_between_emails} delay"
    
    valid_emails.each_with_index do |email_job, index|
      # First email sends immediately, subsequent emails are delayed
      delay = index * delay_between_emails
      
      begin
        # In test environment, don't use delays to avoid issues with job counting
        if Rails.env.test? || delay == 0
          email_job.deliver_later
          Rails.logger.info "[StaggeredEmail] Email #{index + 1}/#{valid_emails.count} scheduled immediately"
        else
          email_job.deliver_later(wait: delay)
          Rails.logger.info "[StaggeredEmail] Email #{index + 1}/#{valid_emails.count} scheduled with #{delay} delay"
        end
      rescue => e
        Rails.logger.error "[StaggeredEmail] Failed to schedule email #{index + 1}: #{e.message}"
      end
    end
  end
  
  # Helper method for order creation emails (common scenario)
  def self.deliver_order_emails(order)
    begin
      # Build email specifications using the new architecture
      email_specs = EmailCollectionBuilder.new
        .add_order_emails(order)
        .build
      
      # Use the new specifications-based delivery
      successful_count = deliver_specifications(email_specs, delay_between_emails: 1.second)
      
      Rails.logger.info "[EMAIL] Scheduled #{successful_count} staggered emails for Order ##{order.order_number}"
      successful_count
    rescue => e
      Rails.logger.error "[EMAIL] Failed to schedule staggered emails for Order ##{order.order_number}: #{e.message}"
      # Don't re-raise the error to prevent disrupting order creation
      0
    end
  end

  # Helper method for booking creation emails
  def self.deliver_booking_emails(booking)
    begin
      # Build email specifications using the new architecture
      email_specs = EmailCollectionBuilder.new
        .add_booking_emails(booking)
        .build
      
      # Use the new specifications-based delivery
      successful_count = deliver_specifications(email_specs, delay_between_emails: 1.second)
      
      Rails.logger.info "[EMAIL] Scheduled #{successful_count} staggered emails for Booking ##{booking.id}"
      successful_count
    rescue => e
      Rails.logger.error "[EMAIL] Failed to schedule staggered emails for Booking ##{booking.id}: #{e.message}"
      # Don't re-raise the error to prevent disrupting booking creation
      0
    end
  end

  # Advanced delivery with different strategies
  def self.deliver_with_strategy(email_specifications, strategy: :time_staggered, **options)
    case strategy
    when :immediate
      deliver_immediately(email_specifications)
    when :time_staggered
      delay = options[:delay_between_emails] || 1.second
      deliver_specifications(email_specifications, delay_between_emails: delay)
    when :batch_staggered
      batch_size = options[:batch_size] || 5
      batch_delay = options[:batch_delay] || 5.seconds
      deliver_in_batches(email_specifications, batch_size: batch_size, batch_delay: batch_delay)
    else
      raise ArgumentError, "Unknown delivery strategy: #{strategy}"
    end
  end

  private
  
  # Deliver all emails immediately
  def self.deliver_immediately(email_specifications)
    Rails.logger.info "[StaggeredEmail] Delivering #{email_specifications.count} emails immediately"
    
    successful_count = 0
    email_specifications.each do |spec|
      successful_count += 1 if spec.execute
    end
    
    Rails.logger.info "[StaggeredEmail] Successfully delivered #{successful_count}/#{email_specifications.count} emails immediately"
    successful_count
  end

  # Deliver emails in batches with delays between batches
  def self.deliver_in_batches(email_specifications, batch_size: 5, batch_delay: 5.seconds)
    Rails.logger.info "[StaggeredEmail] Delivering #{email_specifications.count} emails in batches of #{batch_size} with #{batch_delay} delay"
    
    total_successful = 0
    email_specifications.each_slice(batch_size).with_index do |batch, batch_index|
      delay = batch_index * batch_delay
      
      batch.each do |spec|
        success = if delay == 0
          spec.execute
        else
          spec.execute_with_delay(wait: delay)
        end
        total_successful += 1 if success
      end
      
      Rails.logger.info "[StaggeredEmail] Batch #{batch_index + 1} scheduled with #{delay} delay"
    end
    
    Rails.logger.info "[StaggeredEmail] Successfully scheduled #{total_successful}/#{email_specifications.count} emails in batches"
    total_successful
  end
end 