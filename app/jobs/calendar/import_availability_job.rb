# frozen_string_literal: true

module Calendar
  class ImportAvailabilityJob < ApplicationJob
    queue_as :default

    # Use unique job key to prevent duplicate concurrent jobs for the same staff member
    # This prevents job pile-up when imports take longer than the scheduling interval
    LOCK_TTL = 2.hours

    retry_on Net::ReadTimeout, Net::OpenTimeout, Net::HTTPServerError, wait: :exponentially_longer, attempts: 3
    retry_on ActiveRecord::Deadlocked, wait: 1.second, attempts: 3

    discard_on ActiveRecord::RecordNotFound do |job, error|
      Rails.logger.warn("Discarding availability import job due to missing record: #{error.message}")
    end

    def perform(staff_member_id, start_date = nil, end_date = nil)
      staff_member = StaffMember.find(staff_member_id)

      # Acquire a lock to prevent concurrent imports for the same staff member
      lock_key = "calendar_import:#{staff_member_id}"
      lock_acquired = acquire_lock(lock_key)

      unless lock_acquired
        Rails.logger.info("Skipping calendar import for staff #{staff_member_id} - another import is in progress")
        return
      end

      begin
        # Default to importing next 14 days (reduced from 30 for efficiency)
        start_date ||= Date.current
        end_date ||= 14.days.from_now.to_date

        # Ensure dates are Date objects
        start_date = Date.parse(start_date.to_s) if start_date.is_a?(String)
        end_date = Date.parse(end_date.to_s) if end_date.is_a?(String)

        ActsAsTenant.with_tenant(staff_member.business) do
          sync_coordinator = SyncCoordinator.new
          result = sync_coordinator.import_availability(staff_member, start_date, end_date)

          unless result
            error_message = sync_coordinator.errors.full_messages.join(', ')
            Rails.logger.error("Availability import failed for staff member #{staff_member_id}: #{error_message}")

            if executions < 3
              retry_job(wait: calculate_retry_delay)
            else
              notify_import_failure(staff_member, error_message)
            end
          else
            Rails.logger.info("Successfully imported availability for #{staff_member.name} | Date range: #{start_date} to #{end_date}")

            # Invalidate availability caches so month view updates immediately
            AvailabilityService.clear_staff_availability_cache(staff_member)
          end
        end
      ensure
        release_lock(lock_key)
      end
    end

    # Class method to schedule regular imports for all active staff with calendar connections
    # Now uses batch processing and checks for existing pending jobs
    def self.schedule_for_all_staff(business = nil)
      scope = StaffMember.joins(:calendar_connections)
                        .where(active: true, calendar_connections: { active: true })
                        .select(:id)
                        .distinct

      scope = scope.where(business: business) if business

      # Get IDs of staff members who already have pending import jobs
      pending_staff_ids = pending_import_staff_ids

      scheduled_count = 0
      scope.find_each(batch_size: 100) do |staff_member|
        # Skip if there's already a pending job for this staff member
        next if pending_staff_ids.include?(staff_member.id)

        # Spread jobs across the hour to avoid API rate limits
        delay = rand(0..3600).seconds
        ImportAvailabilityJob.set(wait: delay).perform_later(staff_member.id)
        scheduled_count += 1
      end

      Rails.logger.info("Scheduled #{scheduled_count} calendar import jobs (#{pending_staff_ids.size} already pending)")
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

    def acquire_lock(key)
      # Use Rails cache for distributed locking
      Rails.cache.write(key, Time.current.to_i, expires_in: LOCK_TTL, unless_exist: true)
    end

    def release_lock(key)
      Rails.cache.delete(key)
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
    end

    # Find staff member IDs that already have pending import jobs
    def self.pending_import_staff_ids
      return Set.new unless defined?(SolidQueue::Job)

      pending_jobs = SolidQueue::Job
        .where(class_name: 'Calendar::ImportAvailabilityJob')
        .where(finished_at: nil)
        .pluck(:arguments)

      staff_ids = pending_jobs.map do |args|
        parsed = args.is_a?(String) ? JSON.parse(args) : args
        parsed.dig('arguments', 0)
      rescue
        nil
      end.compact

      Set.new(staff_ids)
    end
  end
end