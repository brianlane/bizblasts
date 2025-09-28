# frozen_string_literal: true

# Initialize the InvalidatedSession cleanup job for session blacklisting
#
# This starts a recurring background job to clean up expired invalidated sessions
# to prevent the table from growing indefinitely.

Rails.application.configure do
  # Start the invalidated session cleanup job after Rails initialization
  config.after_initialize do
    # Only start cleanup in environments where we have background job processing
    if Rails.env.production? || Rails.env.staging?
      # Start the recurring cleanup job
      begin
        InvalidatedSessionCleanupJob.set(wait: 1.hour).perform_later
        Rails.logger.info "[InvalidatedSessionCleanup] Initialized recurring cleanup job"
      rescue => e
        Rails.logger.error "[InvalidatedSessionCleanup] Failed to start cleanup job: #{e.message}"
        # Don't let this prevent application startup
      end
    else
      Rails.logger.debug "[InvalidatedSessionCleanup] Skipping cleanup job in #{Rails.env} environment"
    end
  end
end