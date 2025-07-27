# frozen_string_literal: true

class CalendarSyncService
  # Legacy service that delegates to the new Calendar architecture
  # This maintains backward compatibility while using the new implementation
  
  def self.sync_booking_to_provider(booking, provider = :google)
    Rails.logger.warn("CalendarSyncService.sync_booking_to_provider is deprecated. Use Calendar::SyncCoordinator instead.")
    
    sync_coordinator = Calendar::SyncCoordinator.new
    result = sync_coordinator.sync_booking(booking)
    
    if result
      { success: true, event_id: booking.calendar_event_id }
    else
      { success: false, error: sync_coordinator.errors.full_messages.join(', ') }
    end
  end
  
  def self.update_booking_in_provider(booking, provider = :google)
    Rails.logger.warn("CalendarSyncService.update_booking_in_provider is deprecated. Use Calendar::SyncCoordinator instead.")
    
    sync_coordinator = Calendar::SyncCoordinator.new
    result = sync_coordinator.update_booking(booking)
    
    if result
      { success: true, event_id: booking.calendar_event_id }
    else
      { success: false, error: sync_coordinator.errors.full_messages.join(', ') }
    end
  end
  
  def self.delete_booking_from_provider(booking, provider = :google)
    Rails.logger.warn("CalendarSyncService.delete_booking_from_provider is deprecated. Use Calendar::SyncCoordinator instead.")
    
    sync_coordinator = Calendar::SyncCoordinator.new
    result = sync_coordinator.delete_booking(booking)
    
    if result
      { success: true }
    else
      { success: false, error: sync_coordinator.errors.full_messages.join(', ') }
    end
  end
  
  def self.import_events_from_provider(staff_member, provider = :google, start_date = Date.today, end_date = 30.days.from_now)
    Rails.logger.warn("CalendarSyncService.import_events_from_provider is deprecated. Use Calendar::SyncCoordinator instead.")
    
    return { success: false, error: "Staff member not provided" } unless staff_member
    
    sync_coordinator = Calendar::SyncCoordinator.new
    result = sync_coordinator.import_availability(staff_member, start_date, end_date)
    
    if result
      events = staff_member.calendar_connections.active
                          .flat_map(&:external_calendar_events)
                          .where(starts_at: start_date..end_date)
                          .map do |event|
        {
          id: event.external_event_id,
          summary: event.summary,
          start: event.starts_at,
          end: event.ends_at
        }
      end
      
      { success: true, events: events }
    else
      { success: false, error: sync_coordinator.errors.full_messages.join(', ') }
    end
  end
  
  # New methods for the updated architecture
  
  def self.sync_booking(booking)
    sync_coordinator = Calendar::SyncCoordinator.new
    sync_coordinator.sync_booking(booking)
  end
  
  def self.update_booking(booking)
    sync_coordinator = Calendar::SyncCoordinator.new
    sync_coordinator.update_booking(booking)
  end
  
  def self.delete_booking(booking)
    sync_coordinator = Calendar::SyncCoordinator.new
    sync_coordinator.delete_booking(booking)
  end
  
  def self.import_availability(staff_member, start_date = Date.current, end_date = 30.days.from_now.to_date)
    sync_coordinator = Calendar::SyncCoordinator.new
    sync_coordinator.import_availability(staff_member, start_date, end_date)
  end
  
  # Helper methods for backward compatibility
  
  def self.get_staff_member_from_booking(booking)
    booking.staff_member
  end
  
  # Queue background jobs for async processing
  
  def self.sync_booking_async(booking)
    Calendar::SyncBookingJob.perform_later(booking.id)
  end
  
  def self.delete_booking_async(booking)
    Calendar::DeleteBookingJob.perform_later(booking.id, booking.business_id)
  end
  
  def self.import_availability_async(staff_member, start_date = nil, end_date = nil)
    Calendar::ImportAvailabilityJob.perform_later(staff_member.id, start_date, end_date)
  end
  
  def self.batch_sync_business_async(business)
    Calendar::BatchSyncJob.perform_later(business.id)
  end
  
  # Statistics and monitoring
  
  def self.sync_statistics(business = nil, since = 24.hours.ago)
    sync_coordinator = Calendar::SyncCoordinator.new
    sync_coordinator.sync_statistics(business, since)
  end
  
  def self.retry_failed_syncs(business = nil, limit = 50)
    sync_coordinator = Calendar::SyncCoordinator.new
    sync_coordinator.retry_failed_syncs(business, limit)
  end
end
