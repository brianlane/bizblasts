# frozen_string_literal: true

# Background job to handle cross-domain logout cleanup
# This job performs additional cleanup tasks after a user logs out,
# such as notifying other domains or cleaning up related data
class CrossDomainLogoutJob < ApplicationJob
  queue_as :default

  # Retry with exponential backoff on failure
  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  # Perform cross-domain logout cleanup
  # @param user_id [Integer] ID of the user who logged out
  # @param ip_address [String] IP address where logout was initiated
  def perform(user_id, ip_address = nil)
    start_time = Time.current

    begin
      user = User.find_by(id: user_id)
      unless user
        Rails.logger.warn "[CrossDomainLogoutJob] User #{user_id} not found, skipping cleanup"
        return
      end

      Rails.logger.info "[CrossDomainLogoutJob] Starting cross-domain logout cleanup for user #{user_id}"

      # 1. Ensure all auth tokens for this user are invalidated
      cleanup_auth_tokens(user)

      # 2. Log the logout event for security monitoring
      log_logout_event(user, ip_address)

      # 3. Future: Could send webhook notifications to custom domains
      # notify_custom_domains(user) if user.business&.host_type_custom_domain?

      duration = Time.current - start_time
      Rails.logger.info "[CrossDomainLogoutJob] Completed cleanup for user #{user_id} in #{duration.round(2)}s"

    rescue ActiveRecord::RecordNotFound => e
      Rails.logger.warn "[CrossDomainLogoutJob] User #{user_id} not found: #{e.message}"
    rescue => e
      Rails.logger.error "[CrossDomainLogoutJob] Failed for user #{user_id}: #{e.message}"
      raise e
    end
  end

  private

  # Clean up any remaining auth tokens for the user
  def cleanup_auth_tokens(user)
    begin
      expired_tokens = AuthToken.where(user: user, used: false).count
      if expired_tokens > 0
        AuthToken.where(user: user, used: false).update_all(used: true)
        Rails.logger.info "[CrossDomainLogoutJob] Invalidated #{expired_tokens} unused auth tokens for user #{user.id}"
      end
    rescue => e
      Rails.logger.error "[CrossDomainLogoutJob] Failed to cleanup auth tokens for user #{user.id}: #{e.message}"
    end
  end

  # Log logout event for security monitoring
  def log_logout_event(user, ip_address)
    begin
      Rails.logger.info "[LogoutEvent] User #{user.id} (#{user.email}) logged out from IP #{ip_address}"

      # Future: Could store logout events in a dedicated table for analytics
      # LogoutEvent.create!(user: user, ip_address: ip_address, logged_out_at: Time.current)
    rescue => e
      Rails.logger.error "[CrossDomainLogoutJob] Failed to log logout event for user #{user.id}: #{e.message}"
    end
  end

  # Future enhancement: Notify custom domains about logout
  # This could be useful for immediate cache invalidation or other cleanup
  def notify_custom_domains(user)
    # Implementation would depend on specific requirements
    # Could use webhooks, Redis pub/sub, or other notification mechanisms
  end
end
