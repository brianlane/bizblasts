# frozen_string_literal: true

module Calendar
  class ScheduleImportsJob < ApplicationJob
    queue_as :default

    # This job is scheduled to run every 2 hours via SolidQueue recurring tasks
    # It schedules individual ImportAvailabilityJob instances for each staff member
    # with active calendar connections, with deduplication to prevent job pile-up

    def perform
      Rails.logger.info("Starting scheduled calendar import coordination")

      Calendar::ImportAvailabilityJob.schedule_for_all_staff

      Rails.logger.info("Completed calendar import scheduling")
    end
  end
end
