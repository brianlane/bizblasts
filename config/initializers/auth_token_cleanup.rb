# frozen_string_literal: true

# Initialize the AuthToken cleanup job for cross-domain SSO tokens
#
# This starts a recurring background job to clean up expired auth tokens
# as a failsafe mechanism beyond Redis TTL expiration.

Rails.application.configure do
  # Start the auth token cleanup job after Rails initialization
  config.after_initialize do
    # Only start cleanup in environments where we have background job processing
    if Rails.env.production? || Rails.env.staging?
      # Start the recurring cleanup job
      begin
        AuthTokenCleanupJob.start_recurring_cleanup!
        Rails.logger.info "[AuthTokenCleanup] Initialized recurring cleanup job"
      rescue => e
        Rails.logger.error "[AuthTokenCleanup] Failed to start cleanup job: #{e.message}"
        # Don't let this prevent application startup
      end
    else
      Rails.logger.debug "[AuthTokenCleanup] Skipping cleanup job in #{Rails.env} environment"
    end
  end
end