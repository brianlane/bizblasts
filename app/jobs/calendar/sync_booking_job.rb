# frozen_string_literal: true

module Calendar
  class SyncBookingJob < ApplicationJob
    queue_as :default
    
    retry_on Net::ReadTimeout, Net::OpenTimeout, Net::HTTPServerError, wait: :exponentially_longer, attempts: 3
    retry_on ActiveRecord::Deadlocked, wait: 1.second, attempts: 3
    
    discard_on ActiveRecord::RecordNotFound do |job, error|
      Rails.logger.warn("Discarding job #{job.class.name} due to missing record: #{error.message}")
    end
    
    def perform(booking_id)
      booking = Booking.find(booking_id)
      
      # Set tenant context
      ActsAsTenant.with_tenant(booking.business) do
        sync_coordinator = SyncCoordinator.new
        result = sync_coordinator.sync_booking(booking)
        
        unless result
          error_message = sync_coordinator.errors.full_messages.join(', ')
          Rails.logger.error("Calendar sync failed for booking #{booking_id}: #{error_message}")
          
          # Schedule retry if not already at max attempts
          if executions < 3
            retry_job(wait: calculate_retry_delay)
          else
            booking.update(calendar_event_status: :sync_failed)
            notify_sync_failure(booking, error_message)
          end
        end
      end
    end
    
    private
    
    def calculate_retry_delay
      [executions ** 2, 300].min.seconds
    end
    
    def notify_sync_failure(booking, error_message)
      # Log the failure for monitoring
      Rails.logger.error([
        "Final calendar sync failure for booking #{booking.id}",
        "Staff: #{booking.staff_member&.name}",
        "Service: #{booking.service_name}",
        "Error: #{error_message}"
      ].join(' | '))
      
      # Could send notification to business owner or staff member here
      # NotificationService.send_calendar_sync_failure(booking, error_message)
    end
  end
end