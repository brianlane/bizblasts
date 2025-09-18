# frozen_string_literal: true

# Database-backed authentication token for cross-domain SSO
# Provides secure, short-lived, single-use tokens for session transfer
class AuthToken < ApplicationRecord
  # Token configuration
  TOKEN_TTL = 2.minutes.freeze
  TOKEN_LENGTH = 32
  
  # Associations
  belongs_to :user
  
  # Validations
  validates :token, presence: true, uniqueness: true
  validates :target_url, presence: true
  validates :ip_address, presence: true
  validates :user_agent, presence: true
  validates :expires_at, presence: true
  
  # Scopes
  scope :valid, -> { where(used: false).where('expires_at > ?', Time.current) }
  scope :expired, -> { where('expires_at <= ?', Time.current) }
  
  # Callbacks
  before_validation :set_token, on: :create
  before_validation :set_expires_at, on: :create
  
  class << self
    # Generate and store a new auth token
    # @param user [User] The authenticated user
    # @param target_url [String] The destination URL
    # @param ip_address [String] Client IP address
    # @param user_agent [String] Client user agent
    # @return [AuthToken] The created token
    def create_for_user!(user, target_url, ip_address, user_agent)
      create!(
        user: user,
        target_url: target_url,
        ip_address: ip_address,
        user_agent: user_agent
      )
    end
    
    # Find and validate a token
    # @param token_string [String] The token to find
    # @return [AuthToken, nil] The token if found and valid
    def find_valid(token_string)
      return nil unless token_string.present?
      
      valid.find_by(token: token_string)
    rescue => e
      Rails.logger.error "[AuthToken] Error finding token: #{e.message}"
      nil
    end
    
    # Consume a token (validate and mark as used)
    # @param token_string [String] The token to consume
    # @param current_ip [String] Current request IP
    # @param current_user_agent [String] Current request user agent
    # @return [AuthToken, nil] The consumed token if valid
    def consume!(token_string, current_ip, current_user_agent = nil)
      return nil unless token_string.present?
      
      # Use database transaction to prevent race conditions
      transaction do
        token = valid.lock.find_by(token: token_string)
        return nil unless token
        
        # Validate IP address matches (security check)
        unless token.ip_address == current_ip
          Rails.logger.warn "[AuthToken] IP address mismatch for token #{token_string[0..8]}... (expected: #{token.ip_address}, got: #{current_ip})"
          return nil
        end
        
        # Validate user agent matches (additional security)
        if current_user_agent.present? && token.user_agent != current_user_agent
          Rails.logger.warn "[AuthToken] User agent mismatch for token #{token_string[0..8]}... (expected: #{token.user_agent}, got: #{current_user_agent})"
          # Don't fail on user agent mismatch (mobile vs desktop, etc) but log it
        end
        
        # Mark as used (atomic update)
        token.update!(used: true)
        
        Rails.logger.info "[AuthToken] Successfully consumed token for user #{token.user_id}"
        return token
      end
    rescue => e
      Rails.logger.error "[AuthToken] Error during token consumption: #{e.message}"
      nil
    end
    
    # Clean up expired tokens (called by background job)
    def cleanup_expired!
      expired_count = expired.delete_all
      Rails.logger.info "[AuthToken] Cleaned up #{expired_count} expired tokens" if expired_count > 0
      expired_count
    end
    
    private
    
    # Generate a cryptographically secure token
    def generate_auth_token
      SecureRandom.urlsafe_base64(TOKEN_LENGTH)
    end
  end
  
  # Check if token is expired
  def expired?
    expires_at <= Time.current
  end
  
  # Check if token is still valid for consumption (not used and not expired)
  def consumable?
    !used? && !expired?
  end
  
  private
  
  def set_token
    return if token.present?
    self.token = SecureRandom.urlsafe_base64(TOKEN_LENGTH)
  end
  
  def set_expires_at
    self.expires_at ||= TOKEN_TTL.from_now
  end
end