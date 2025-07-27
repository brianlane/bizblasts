# frozen_string_literal: true

module Calendar
  class BatchSyncJob < ApplicationJob
    queue_as :default
    
    retry_on Net::TimeoutError, Net::HTTPServerError, wait: :exponentially_longer, attempts: 2
    retry_on ActiveRecord::DeadlockRetry, wait: 1.second, attempts: 3
    
    def perform(business_id, options = {})
      business = Business.find(business_id)
      
      ActsAsTenant.with_tenant(business) do
        sync_coordinator = SyncCoordinator.new
        
        case options['action']
        when 'retry_failed'
          retry_failed_syncs(sync_coordinator, business, options)
        when 'sync_pending'
          sync_pending_bookings(sync_coordinator, business, options)
        when 'import_all_availability'
          import_all_availability(sync_coordinator, business, options)
        else
          sync_all_bookings(sync_coordinator, business, options)
        end
      end
    end
    
    # Schedule batch operations
    def self.retry_failed_syncs_for_business(business_id, limit: 50)
      perform_later(business_id, {
        'action' => 'retry_failed',
        'limit' => limit
      })
    end
    
    def self.sync_pending_bookings_for_business(business_id, limit: 100)
      perform_later(business_id, {
        'action' => 'sync_pending',
        'limit' => limit
      })
    end
    
    def self.import_availability_for_business(business_id, days_ahead: 30)
      perform_later(business_id, {
        'action' => 'import_all_availability',
        'days_ahead' => days_ahead
      })
    end
    
    def self.full_sync_for_business(business_id, limit: 200)
      perform_later(business_id, {
        'action' => 'full_sync',
        'limit' => limit
      })
    end
    
    private
    
    def retry_failed_syncs(sync_coordinator, business, options)
      limit = options['limit'] || 50
      
      Rails.logger.info("Starting retry of failed syncs for business #{business.id}")
      
      result = sync_coordinator.retry_failed_syncs(business, limit)
      
      Rails.logger.info([
        "Completed retry of failed syncs for business #{business.id}:",
        "Attempted: #{result[:total_attempted]}",
        "Successful: #{result[:successful]}",
        "Failed: #{result[:failed]}"
      ].join(' '))
    rescue => e
      Rails.logger.error("Batch retry failed syncs error for business #{business.id}: #{e.message}")
      raise e
    end
    
    def sync_pending_bookings(sync_coordinator, business, options)
      limit = options['limit'] || 100
      
      Rails.logger.info("Starting sync of pending bookings for business #{business.id}")
      
      pending_bookings = business.bookings
                               .where(calendar_event_status: [:not_synced, :sync_pending])
                               .includes(:staff_member, :service, :tenant_customer)
                               .limit(limit)
      
      successful = 0
      failed = 0
      
      pending_bookings.find_each do |booking|
        if sync_coordinator.sync_booking(booking)
          successful += 1
        else
          failed += 1
        end
        
        # Small delay to respect API rate limits
        sleep(0.1) if pending_bookings.count > 10
      end
      
      Rails.logger.info([
        "Completed sync of pending bookings for business #{business.id}:",
        "Successful: #{successful}",
        "Failed: #{failed}"
      ].join(' '))
    rescue => e
      Rails.logger.error("Batch sync pending bookings error for business #{business.id}: #{e.message}")
      raise e
    end
    
    def import_all_availability(sync_coordinator, business, options)
      days_ahead = options['days_ahead'] || 30
      start_date = Date.current
      end_date = days_ahead.days.from_now.to_date
      
      Rails.logger.info([
        "Starting availability import for business #{business.id}",
        "Date range: #{start_date} to #{end_date}"
      ].join(' | '))
      
      staff_members = business.staff_members
                            .joins(:calendar_connections)
                            .where(active: true, calendar_connections: { active: true })
                            .distinct
      
      successful = 0
      failed = 0
      
      staff_members.each do |staff_member|
        if sync_coordinator.import_availability(staff_member, start_date, end_date)
          successful += 1
        else
          failed += 1
        end
        
        # Delay between staff members to respect API rate limits
        sleep(1) if staff_members.count > 5
      end
      
      Rails.logger.info([
        "Completed availability import for business #{business.id}:",
        "Staff processed: #{staff_members.count}",
        "Successful: #{successful}",
        "Failed: #{failed}"
      ].join(' '))
    rescue => e
      Rails.logger.error("Batch availability import error for business #{business.id}: #{e.message}")
      raise e
    end
    
    def sync_all_bookings(sync_coordinator, business, options)
      limit = options['limit'] || 200
      
      Rails.logger.info("Starting full sync for business #{business.id}")
      
      # Get recent and upcoming bookings that need sync
      bookings = business.bookings
                       .where(start_time: 7.days.ago..30.days.from_now)
                       .where.not(status: :cancelled)
                       .includes(:staff_member, :service, :tenant_customer)
                       .limit(limit)
      
      # Group by staff member for efficient processing
      grouped_bookings = bookings.group_by(&:staff_member_id)
      
      total_processed = 0
      total_successful = 0
      
      grouped_bookings.each do |staff_member_id, staff_bookings|
        staff_member = StaffMember.find(staff_member_id)
        next unless staff_member.has_calendar_integrations?
        
        staff_bookings.each do |booking|
          if sync_coordinator.sync_booking(booking)
            total_successful += 1
          end
          total_processed += 1
        end
        
        # Delay between staff members
        sleep(0.5) if grouped_bookings.count > 3
      end
      
      Rails.logger.info([
        "Completed full sync for business #{business.id}:",
        "Processed: #{total_processed}",
        "Successful: #{total_successful}",
        "Failed: #{total_processed - total_successful}"
      ].join(' '))
    rescue => e
      Rails.logger.error("Batch full sync error for business #{business.id}: #{e.message}")
      raise e
    end
  end
end