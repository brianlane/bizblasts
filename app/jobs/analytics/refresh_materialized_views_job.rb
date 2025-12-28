# frozen_string_literal: true

module Analytics
  # Job to refresh analytics materialized views
  # Schedule: Run hourly or daily depending on data freshness requirements
  # Example: Sidekiq-Cron or similar scheduler
  class RefreshMaterializedViewsJob < ApplicationJob
    queue_as :low

    VIEWS = %w[
      daily_analytics_summaries
      traffic_source_summaries
      top_pages_summaries
    ].freeze

    def perform(concurrently: true)
      Rails.logger.info "[Analytics] Starting materialized view refresh"
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      results = {}

      VIEWS.each do |view_name|
        view_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        begin
          refresh_view(view_name, concurrently: concurrently)
          elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - view_start
          results[view_name] = { success: true, duration: elapsed.round(3) }
          Rails.logger.info "[Analytics] Refreshed #{view_name} in #{elapsed.round(3)}s"
        rescue StandardError => e
          elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - view_start
          results[view_name] = { success: false, error: e.message, duration: elapsed.round(3) }
          Rails.logger.error "[Analytics] Failed to refresh #{view_name}: #{e.message}"
        end
      end

      total_elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
      Rails.logger.info "[Analytics] Materialized view refresh complete in #{total_elapsed.round(3)}s"

      results
    end

    private

    def refresh_view(view_name, concurrently:)
      # Validate view name to prevent SQL injection
      raise ArgumentError, "Invalid view name: #{view_name}" unless VIEWS.include?(view_name)

      # Use CONCURRENTLY if the view has a unique index (allows reads during refresh)
      # Falls back to regular refresh if CONCURRENTLY fails
      if concurrently
        begin
          ActiveRecord::Base.connection.execute(
            "REFRESH MATERIALIZED VIEW CONCURRENTLY #{view_name}"
          )
        rescue ActiveRecord::StatementInvalid => e
          # CONCURRENTLY requires a unique index - fall back to regular refresh
          if e.message.include?("cannot refresh materialized view")
            Rails.logger.warn "[Analytics] Falling back to non-concurrent refresh for #{view_name}"
            ActiveRecord::Base.connection.execute(
              "REFRESH MATERIALIZED VIEW #{view_name}"
            )
          else
            raise
          end
        end
      else
        ActiveRecord::Base.connection.execute(
          "REFRESH MATERIALIZED VIEW #{view_name}"
        )
      end
    end
  end
end
