# frozen_string_literal: true

module Calendar
  class DeleteBookingJob < ApplicationJob
    queue_as :default
    
    retry_on Net::TimeoutError, Net::HTTPServerError, wait: :exponentially_longer, attempts: 3
    retry_on ActiveRecord::DeadlockRetry, wait: 1.second, attempts: 3
    
    def perform(booking_id, business_id)
      # We get business_id separately because booking might be deleted
      business = Business.find(business_id)
      
      ActsAsTenant.with_tenant(business) do
        # Try to find the booking first
        booking = Booking.find_by(id: booking_id)
        
        if booking
          # Booking still exists, use normal sync coordinator
          sync_coordinator = SyncCoordinator.new
          result = sync_coordinator.delete_booking(booking)
          
          unless result
            error_message = sync_coordinator.errors.full_messages.join(', ')
            Rails.logger.error("Calendar deletion failed for booking #{booking_id}: #{error_message}")
            
            if executions < 3
              retry_job(wait: calculate_retry_delay)
            end
          end
        else
          # Booking was deleted, clean up any orphaned calendar mappings
          cleanup_orphaned_mappings(booking_id, business)
        end
      end
    end
    
    private
    
    def cleanup_orphaned_mappings(booking_id, business)
      # Find any calendar event mappings that reference the deleted booking
      mappings = CalendarEventMapping.joins(:calendar_connection)
                                    .where(
                                      booking_id: booking_id,
                                      calendar_connections: { business_id: business.id }
                                    )
      
      mappings.each do |mapping|
        next unless mapping.calendar_connection.active?
        
        service = service_for_connection(mapping.calendar_connection)
        next unless service
        
        begin
          service.delete_event(mapping.external_event_id)
          mapping.mark_deleted!
          Rails.logger.info("Cleaned up orphaned calendar event: #{mapping.external_event_id}")
        rescue => e
          Rails.logger.error("Failed to clean up calendar event #{mapping.external_event_id}: #{e.message}")
          mapping.mark_failed!("Cleanup failed: #{e.message}")
        end
      end
    end
    
    def service_for_connection(connection)
      case connection.provider
      when 'google'
        Calendar::GoogleService.new(connection)
      when 'microsoft'
        Calendar::MicrosoftService.new(connection)
      else
        nil
      end
    end
    
    def calculate_retry_delay
      [executions ** 2, 300].min.seconds
    end
  end
end