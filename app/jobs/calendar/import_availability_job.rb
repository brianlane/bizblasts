# frozen_string_literal: true

module Calendar
  class ImportAvailabilityJob < ApplicationJob
    queue_as :default
    
    retry_on Net::ReadTimeout, Net::OpenTimeout, Net::HTTPServerError, wait: :exponentially_longer, attempts: 3
    retry_on ActiveRecord::Deadlocked, wait: 1.second, attempts: 3
    
    discard_on ActiveRecord::RecordNotFound do |job, error|
      Rails.logger.warn("Discarding availability import job due to missing record: #{error.message}")
    end
    
    def perform(staff_member_id, start_date = nil, end_date = nil)
      staff_member = StaffMember.find(staff_member_id)
      
      # Default to importing next 30 days
      start_date ||= Date.current
      end_date ||= 30.days.from_now.to_date
      
      # Ensure dates are Date objects
      start_date = Date.parse(start_date.to_s) if start_date.is_a?(String)
      end_date = Date.parse(end_date.to_s) if end_date.is_a?(String)
      
      ActsAsTenant.with_tenant(staff_member.business) do
        sync_coordinator = SyncCoordinator.new
        result = sync_coordinator.import_availability(staff_member, start_date, end_date)
        
        unless result
          error_message = sync_coordinator.errors.full_messages.join(', ')
          Rails.logger.error([
            "Availability import failed for staff member #{staff_member_id}:",
            error_message
          ].join(' '))
          
          if executions < 3
            retry_job(wait: calculate_retry_delay)
          else
            notify_import_failure(staff_member, error_message)
          end
        else
          Rails.logger.info([
            "Successfully imported availability for #{staff_member.name}",
            "Date range: #{start_date} to #{end_date}"
          ].join(' | '))
          
          # Invalidate availability caches so month view updates immediately
          AvailabilityService.clear_staff_availability_cache(staff_member)
          
          # Schedule next import
          schedule_next_import(staff_member_id)
        end
      end
    end
    
    # Class method to schedule regular imports for all active staff with calendar connections
    def self.schedule_for_all_staff(business = nil)
      scope = StaffMember.joins(:calendar_connections)
                        .where(active: true, calendar_connections: { active: true })
                        .distinct
      
      scope = scope.where(business: business) if business
      
      scope.find_each do |staff_member|
        # Schedule import to run within the next hour, spread out to avoid API rate limits
        delay = rand(0..3600).seconds
        ImportAvailabilityJob.set(wait: delay).perform_later(staff_member.id)
      end
    end
    
    # Schedule import for specific date range (useful for booking conflicts)
    def self.import_for_date_range(staff_member_id, start_date, end_date, priority: false)
      job_options = priority ? { queue: :high_priority } : {}
      
      ImportAvailabilityJob.set(job_options).perform_later(
        staff_member_id,
        start_date,
        end_date
      )
    end
    
    private
    
    def schedule_next_import(staff_member_id)
      # Schedule next import in 4-6 hours with some randomization
      next_import_delay = (4.hours + rand(0..2.hours))
      
      ImportAvailabilityJob.set(wait: next_import_delay).perform_later(staff_member_id)
    end
    
    def calculate_retry_delay
      [executions ** 2, 300].min.seconds
    end
    
    def notify_import_failure(staff_member, error_message)
      Rails.logger.error([
        "Final availability import failure for staff member #{staff_member.id}",
        "Staff: #{staff_member.name}",
        "Business: #{staff_member.business.name}",
        "Error: #{error_message}"
      ].join(' | '))
      
      # Could send notification to business owner here
      # NotificationService.send_availability_import_failure(staff_member, error_message)
    end
  end
end