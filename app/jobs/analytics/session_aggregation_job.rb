# frozen_string_literal: true

module Analytics
  # Job for closing inactive sessions and updating their metrics
  # Runs hourly to process sessions that have been inactive for 30+ minutes
  class SessionAggregationJob < ApplicationJob
    queue_as :analytics

    # Session timeout in minutes
    SESSION_TIMEOUT = 30

    def perform
      Rails.logger.info "[SessionAggregation] Starting session aggregation..."
      
      # Process sessions for each business
      Business.active.find_each do |business|
        process_business_sessions(business)
      rescue StandardError => e
        Rails.logger.error "[SessionAggregation] Error processing business #{business.id}: #{e.message}"
      end
      
      Rails.logger.info "[SessionAggregation] Session aggregation complete"
    end

    private

    def process_business_sessions(business)
      ActsAsTenant.with_tenant(business) do
        # Find sessions that are still open but inactive based on last activity time
        # A session is inactive if there has been no page view or click event for SESSION_TIMEOUT minutes
        cutoff_time = SESSION_TIMEOUT.minutes.ago

        inactive_sessions = business.visitor_sessions
          .where(session_end: nil)
          .left_joins(:page_views, :click_events)
          .group('visitor_sessions.id')
          .having(
            'COALESCE(MAX(page_views.created_at), MAX(click_events.created_at), visitor_sessions.session_start) < ?',
            cutoff_time
          )
        
        closed_count = 0
        
        inactive_sessions.find_each do |session|
          close_session(session)
          closed_count += 1
        end
        
        if closed_count > 0
          Rails.logger.info "[SessionAggregation] Closed #{closed_count} sessions for business #{business.id}"
        end
      end
    end

    def close_session(session)
      # Calculate final session metrics
      last_activity = session.page_views.maximum(:created_at) || 
                      session.click_events.maximum(:created_at) ||
                      session.session_start
      
      duration = (last_activity - session.session_start).to_i
      is_bounce = session.page_view_count <= 1
      
      # Get the exit page
      exit_page = session.page_views.order(created_at: :desc).first&.page_path
      
      # Update session with final metrics
      session.update!(
        session_end: last_activity,
        duration_seconds: duration,
        is_bounce: is_bounce,
        exit_page: exit_page,
        pages_visited: session.page_views.distinct.count(:page_path)
      )
      
      # Mark the last page view as exit page
      last_page_view = session.page_views.order(created_at: :desc).first
      last_page_view&.update!(is_exit_page: true)
    end
  end
end

