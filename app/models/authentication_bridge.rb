class AuthenticationBridge < ApplicationRecord
  belongs_to :user
  
  # Token expires in 5 minutes - short-lived for security
  TOKEN_LIFETIME = 5.minutes
  
  # Maximum number of unused tokens per user
  MAX_TOKENS_PER_USER = 5
  
  validates :token, presence: true, uniqueness: true
  validates :expires_at, presence: true
  validates :target_url, presence: true
  validates :source_ip, presence: true
  
  # Scopes for cleanup and security
  scope :expired, -> { where('expires_at < ?', Time.current) }
  scope :unused, -> { where(used_at: nil) }
  scope :used, -> { where.not(used_at: nil) }
  scope :for_user, ->(user) { where(user: user) }
  
  # Generate a new authentication bridge token
  def self.create_for_user!(user, target_url, request_ip, user_agent)
    # Cleanup old tokens for this user first
    cleanup_old_tokens_for_user(user)
    
    token = generate_secure_token
    
    create!(
      user: user,
      token: token,
      target_url: target_url,
      expires_at: TOKEN_LIFETIME.from_now,
      source_ip: request_ip,
      user_agent: user_agent&.truncate(500)
    )
  end
  
  # Find and consume a valid token
  def self.consume_token!(token, request_ip)
    bridge = find_by(token: token)
    
    # Validate token exists and is not expired
    return nil unless bridge&.valid_for_consumption?(request_ip)
    
    # Mark as used
    bridge.update!(used_at: Time.current)
    bridge
  end
  
  # Check if token is valid for consumption
  def valid_for_consumption?(request_ip)
    return false if used_at.present? # Already used
    return false if expires_at < Time.current # Expired
    return false if source_ip != request_ip # IP mismatch for security
    
    true
  end
  
  # Check if token is expired
  def expired?
    expires_at < Time.current
  end
  
  # Check if token has been used
  def used?
    used_at.present?
  end
  
  # Cleanup expired and old tokens
  def self.cleanup_expired_tokens!
    expired.delete_all
    
    # Also cleanup old used tokens (older than 1 hour)
    used.where('used_at < ?', 1.hour.ago).delete_all
  end
  
  private
  
  def self.cleanup_old_tokens_for_user(user)
    # Remove expired tokens
    for_user(user).expired.delete_all
    
    # Keep only the most recent unused tokens, delete older ones
    old_tokens = for_user(user).unused.order(created_at: :desc).offset(MAX_TOKENS_PER_USER)
    old_tokens.delete_all if old_tokens.exists?
  end
  
  def self.generate_secure_token
    SecureRandom.hex(32) # 64 character token
  end
end
