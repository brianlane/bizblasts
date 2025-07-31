# frozen_string_literal: true

module Calendar
  class SyncCoordinator
    include ActiveModel::Validations
    
    attr_reader :errors
    
    def initialize
      @errors = ActiveModel::Errors.new(self)
    end
    
    # Sync a single booking to all connected calendars
    def sync_booking(booking)
      return false unless booking.is_a?(Booking)
      
      staff_member = booking.staff_member
      return false unless staff_member
      
      connections = staff_member.calendar_connections.active
      return true if connections.empty? # No calendars to sync to
      
      results = []
      
      connections.each do |connection|
        result = sync_booking_to_connection(booking, connection)
        results << result
      end
      
      # Update booking status based on results
      update_booking_sync_status(booking, results)
      
      results.all? { |r| r[:success] }
    end
    
    # Update a booking in all connected calendars
    def update_booking(booking)
      return false unless booking.is_a?(Booking)
      
      mappings = booking.calendar_event_mappings.includes(:calendar_connection)
      return true if mappings.empty?
      
      results = []
      
      mappings.each do |mapping|
        next unless mapping.calendar_connection.active?
        
        result = update_booking_in_connection(booking, mapping)
        results << result
      end
      
      update_booking_sync_status(booking, results)
      results.all? { |r| r[:success] }
    end
    
    # Delete a booking from all connected calendars
    def delete_booking(booking)
      return false unless booking.is_a?(Booking)
      
      mappings = booking.calendar_event_mappings.includes(:calendar_connection)
      return true if mappings.empty?
      
      results = []
      
      mappings.each do |mapping|
        next unless mapping.calendar_connection.active?
        
        result = delete_booking_from_connection(mapping)
        results << result
      end
      
      results.all? { |r| r[:success] }
    end
    
    # Import events from all active calendar connections for availability checking
    def import_availability(staff_member, start_date = Date.current, end_date = 30.days.from_now.to_date)
      return false unless staff_member.is_a?(StaffMember)
      
      connections = staff_member.calendar_connections.active
      return true if connections.empty?
      
      results = []
      
      connections.each do |connection|
        result = import_events_from_connection(connection, start_date, end_date)
        results << result
      end
      
      results.all? { |r| r[:success] }
    end
    
    # Batch sync multiple bookings efficiently
    def batch_sync_bookings(bookings)
      return false unless bookings.is_a?(Array)
      
      grouped_bookings = bookings.group_by(&:staff_member_id)
      all_results = []
      
      grouped_bookings.each do |staff_member_id, staff_bookings|
        staff_member = StaffMember.find(staff_member_id)
        connections = staff_member.calendar_connections.active
        
        connections.each do |connection|
          service = service_for_connection(connection)
          next unless service
          
          staff_bookings.each do |booking|
            result = sync_booking_to_connection(booking, connection)
            all_results << result
          end
        end
      end
      
      all_results.all? { |r| r[:success] }
    end
    
    # Force resync of failed bookings
    def retry_failed_syncs(business = nil, limit = 50)
      failed_mappings = CalendarEventMapping.needs_sync
                                           .includes(:booking, :calendar_connection)
                                           .limit(limit)
      
      if business
        failed_mappings = failed_mappings.joins(:booking)
                                        .where(bookings: { business_id: business.id })
      end
      
      results = []
      
      failed_mappings.each do |mapping|
        next unless mapping.calendar_connection.active?
        next unless mapping.can_retry?
        
        result = sync_booking_to_connection(mapping.booking, mapping.calendar_connection)
        results << result
      end
      
      {
        total_attempted: results.count,
        successful: results.count { |r| r[:success] },
        failed: results.count { |r| !r[:success] }
      }
    end
    
    # Get sync statistics for monitoring
    def sync_statistics(business = nil, since = 24.hours.ago)
      base_scope = CalendarSyncLog.where(created_at: since..)
      
      if business
        base_scope = base_scope.joins(calendar_event_mapping: { booking: :business })
                              .where(businesses: { id: business.id })
      end
      
      {
        total_attempts: base_scope.count,
        successful: base_scope.successful_syncs.count,
        failed: base_scope.failed_attempts.count,
        success_rate: CalendarSyncLog.success_rate_for_provider('google', since: since),
        recent_failures: CalendarSyncLog.recent_failures(limit: 10)
      }
    end
    
    private
    
    def sync_booking_to_connection(booking, connection)
      service = service_for_connection(connection)
      return { success: false, error: "Service not available" } unless service
      
      # Check if mapping already exists
      existing_mapping = connection.calendar_event_mappings.find_by(booking: booking)
      
      if existing_mapping
        # Update existing event
        result = service.update_event(booking, existing_mapping.external_event_id)
      else
        # Create new event
        result = service.create_event(booking)
      end
      
      if result && result[:success]
        { success: true, mapping: result[:mapping] }
      else
        error_message = service.errors.full_messages.join(', ')
        { success: false, error: error_message }
      end
    rescue => e
      Rails.logger.error("Calendar sync failed for booking #{booking.id}: #{e.message}")
      { success: false, error: e.message }
    end
    
    def update_booking_in_connection(booking, mapping)
      service = service_for_connection(mapping.calendar_connection)
      return { success: false, error: "Service not available" } unless service
      
      result = service.update_event(booking, mapping.external_event_id)
      
      if result && result[:success]
        { success: true, mapping: result[:mapping] }
      else
        error_message = service.errors.full_messages.join(', ')
        mapping.mark_failed!(error_message)
        { success: false, error: error_message }
      end
    rescue => e
      Rails.logger.error("Calendar update failed for booking #{booking.id}: #{e.message}")
      mapping.mark_failed!(e.message)
      { success: false, error: e.message }
    end
    
    def delete_booking_from_connection(mapping)
      service = service_for_connection(mapping.calendar_connection)
      return { success: false, error: "Service not available" } unless service
      
      result = service.delete_event(mapping.external_event_id)
      
      if result && result[:success]
        mapping.mark_deleted!
        { success: true }
      else
        error_message = service.errors.full_messages.join(', ')
        mapping.mark_failed!(error_message)
        { success: false, error: error_message }
      end
    rescue => e
      Rails.logger.error("Calendar delete failed for mapping #{mapping.id}: #{e.message}")
      mapping.mark_failed!(e.message)
      { success: false, error: e.message }
    end
    
    def import_events_from_connection(connection, start_date, end_date)
      service = service_for_connection(connection)
      return { success: false, error: "Service not available" } unless service
      
      result = service.import_events(start_date, end_date)
      
      if result && result[:success]
        { success: true, imported_count: result[:imported_count] }
      else
        error_message = service.errors.full_messages.join(', ')
        { success: false, error: error_message }
      end
    rescue => e
      Rails.logger.error("Calendar import failed for connection #{connection.id}: #{e.message}")
      { success: false, error: e.message }
    end
    
    def service_for_connection(connection)
      case connection.provider
      when 'google'
        GoogleService.new(connection)
      when 'microsoft'
        MicrosoftService.new(connection)
      else
        Rails.logger.warn("Unsupported calendar provider: #{connection.provider}")
        nil
      end
    end
    
    def update_booking_sync_status(booking, results)
      if results.all? { |r| r[:success] }
        booking.update(calendar_event_status: :synced)
      elsif results.any? { |r| r[:success] }
        booking.update(calendar_event_status: :sync_pending)
      else
        booking.update(calendar_event_status: :sync_failed)
      end
    end
    
    def add_error(type, message)
      @errors.add(type, message)
      Rails.logger.error("[Calendar::SyncCoordinator] #{type}: #{message}")
    end
  end
end