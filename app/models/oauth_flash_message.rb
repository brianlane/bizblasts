# Stores flash messages for OAuth callbacks using database-backed tokens
# instead of URL parameters to avoid CodeQL security warnings about
# sensitive data in GET requests.
class OauthFlashMessage < ApplicationRecord
  # Token expires after 5 minutes - enough time for OAuth redirect flow
  DEFAULT_EXPIRATION = 5.minutes

  validates :token, presence: true, uniqueness: true
  validates :expires_at, presence: true

  # Scopes for cleanup
  scope :expired, -> { where('expires_at < ?', Time.current) }
  scope :used_or_expired, -> { where('used = ? OR expires_at < ?', true, Time.current) }

  # Create a new flash message and return the token
  # @param notice [String, nil] Success message
  # @param alert [String, nil] Error message
  # @return [String] The token to use in redirect URL
  def self.create_with_token(notice: nil, alert: nil)
    token = SecureRandom.urlsafe_base64(32)
    create!(
      token: token,
      notice: notice,
      alert: alert,
      expires_at: DEFAULT_EXPIRATION.from_now
    )
    token
  end

  # Consume a flash message token and return the messages
  # Returns nil if token is invalid, expired, or already used
  # @param token [String] The token from the URL
  # @return [Hash, nil] Hash with :notice and :alert keys, or nil if invalid
  def self.consume(token)
    return nil if token.blank?

    record = find_by(token: token)
    return nil unless record
    return nil if record.used?
    return nil if record.expires_at < Time.current

    # Mark as used atomically to prevent race conditions
    updated = where(id: record.id, used: false)
              .update_all(used: true, updated_at: Time.current)
    return nil if updated == 0

    { notice: record.notice, alert: record.alert }.compact
  end

  # Clean up old records - call from scheduled job
  def self.cleanup_old_records
    deleted_count = used_or_expired.delete_all
    Rails.logger.info "[OauthFlashMessage] Cleaned up #{deleted_count} old records"
    deleted_count
  end
end
