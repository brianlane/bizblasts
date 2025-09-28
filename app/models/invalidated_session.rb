# frozen_string_literal: true

# Model to track invalidated sessions for reliable cross-domain logout
# This provides server-side session blacklisting that works across all domains
class InvalidatedSession < ApplicationRecord
  belongs_to :user

  # Validations
  validates :session_token, presence: true, uniqueness: true
  validates :invalidated_at, presence: true
  validates :expires_at, presence: true

  # Scopes
  scope :active, -> { where('expires_at > ?', Time.current) }
  scope :expired, -> { where('expires_at <= ?', Time.current) }

  # Class methods
  class << self
    # Clean up expired blacklist entries
    # Called by background job to prevent table growth
    def cleanup_expired!
      expired_count = expired.delete_all
      Rails.logger.info "[InvalidatedSession] Cleaned up #{expired_count} expired entries" if expired_count > 0
      expired_count
    end

    # Check if a session token is blacklisted
    # This is the primary method used by ApplicationController
    def session_blacklisted?(session_token)
      return false unless session_token.present?

      Rails.cache.fetch("blacklisted_session:#{session_token}", expires_in: 5.minutes) do
        active.exists?(session_token: session_token)
      end
    end

    # Blacklist a session token
    # Creates a new blacklist entry with appropriate TTL
    def blacklist_session!(user, session_token, ttl: Rails.application.config.x.auth_bridge&.session_blacklist_ttl || 24.hours)
      return unless user && session_token.present?

      create!(
        user: user,
        session_token: session_token,
        invalidated_at: Time.current,
        expires_at: ttl.from_now
      )

      # Invalidate cache for this session token
      Rails.cache.delete("blacklisted_session:#{session_token}")

    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
      # Session already blacklisted, which is fine
      if e.message.include?('already been taken') || e.is_a?(ActiveRecord::RecordNotUnique)
        Rails.logger.debug "[InvalidatedSession] Session #{session_token[0..8]}... already blacklisted"
      else
        raise e
      end
    end
  end

  # Instance methods
  def expired?
    expires_at <= Time.current
  end

  def active?
    !expired?
  end
end
