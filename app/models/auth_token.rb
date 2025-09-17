# frozen_string_literal: true

# Redis-backed authentication token for cross-domain SSO
# Provides secure, short-lived, single-use tokens for session transfer
class AuthToken
  include ActiveModel::Model
  include ActiveModel::Attributes
  
  # Token configuration
  TOKEN_TTL = 2.minutes.freeze
  TOKEN_LENGTH = 32
  REDIS_KEY_PREFIX = 'auth_token'
  
  # Attributes
  attribute :token, :string
  attribute :user_id, :integer
  attribute :target_url, :string
  attribute :ip_address, :string
  attribute :user_agent, :string
  attribute :created_at, :datetime
  attribute :used, :boolean, default: false
  
  validates :user_id, presence: true
  validates :target_url, presence: true
  validates :ip_address, presence: true
  validates :user_agent, presence: true
  
  class << self
    # Generate and store a new auth token
    # @param user [User] The authenticated user
    # @param target_url [String] The destination URL
    # @param ip_address [String] Client IP address
    # @param user_agent [String] Client user agent
    # @return [AuthToken] The created token
    def create_for_user!(user, target_url, ip_address, user_agent)
      token = new(
        token: generate_secure_token,
        user_id: user.id,
        target_url: target_url,
        ip_address: ip_address,
        user_agent: user_agent,
        created_at: Time.current,
        used: false
      )
      
      token.validate!
      token.save!
      token
    end
    
    # Find and validate a token
    # @param token_string [String] The token to find
    # @return [AuthToken, nil] The token if found and valid
    def find_valid(token_string)
      return nil unless token_string.present?
      
      data = redis.get(redis_key(token_string))
      return nil unless data
      
      token_data = JSON.parse(data)
      new(token_data.merge('token' => token_string))
    rescue JSON::ParserError, Redis::BaseError => e
      Rails.logger.error "[AuthToken] Error finding token: #{e.message}"
      nil
    end
    
    # Consume a token (validate and mark as used)
    # @param token_string [String] The token to consume
    # @param current_ip [String] Current request IP
    # @param current_user_agent [String] Current request user agent
    # @return [AuthToken, nil] The token if successfully consumed
    def consume!(token_string, current_ip, current_user_agent = nil)
      return nil unless token_string.present?
      
      redis_key = redis_key(token_string)
      
      # Atomic consumption using Redis WATCH/MULTI/EXEC to prevent race conditions
      loop do
        redis.watch(redis_key)
        
        # Get token data while watched
        data = redis.get(redis_key)
        return nil unless data
        
        begin
          token_data = JSON.parse(data)
          token = new(token_data.merge('token' => token_string))
        rescue JSON::ParserError => e
          Rails.logger.error "[AuthToken] Error parsing token data: #{e.message}"
          redis.unwatch
          return nil
        end
        
        # Validate token hasn't been used
        if token.used?
          redis.unwatch
          return nil
        end
        
        # Validate IP address matches (security check)
        unless token.ip_address == current_ip
          redis.unwatch
          Rails.logger.warn "[AuthToken] IP address mismatch for token #{token_string[0..8]}... (expected: #{token.ip_address}, got: #{current_ip})"
          return nil
        end
        
        # Validate user agent matches (additional security)
        if current_user_agent.present? && token.user_agent != current_user_agent
          Rails.logger.warn "[AuthToken] User agent mismatch for token #{token_string[0..8]}... (expected: #{token.user_agent}, got: #{current_user_agent})"
          # Don't fail on user agent mismatch (mobile vs desktop, etc) but log it
        end
        
        # Atomic delete operation - prevents double consumption
        result = redis.multi do |multi|
          multi.del(redis_key)
        end
        
        # If WATCH detected a change, result will be nil and we retry
        if result
          Rails.logger.info "[AuthToken] Successfully consumed and deleted token for user #{token.user_id}"
          return token
        end
        
        # Token was modified during our operation, retry
        Rails.logger.debug "[AuthToken] Token modified during consumption, retrying..."
      end
    rescue Redis::BaseError => e
      Rails.logger.error "[AuthToken] Redis error during token consumption: #{e.message}"
      nil
    end
    
    # Generate a cryptographically secure token
    # @return [String] The generated token
    def generate_secure_token
      SecureRandom.urlsafe_base64(TOKEN_LENGTH)
    end
    
    # Get Redis key for a token
    # @param token [String] The token
    # @return [String] The Redis key
    def redis_key(token)
      "#{REDIS_KEY_PREFIX}:#{token}"
    end
    
    # Get Redis connection
    # @return [Redis] Redis connection
    def redis
      @redis ||= if Rails.application.config.respond_to?(:redis)
                   Rails.application.config.redis
                 else
                   Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'))
                 end
    end
    
    # Clean up expired tokens (background job helper)
    # @return [Integer] Number of tokens cleaned up
    def cleanup_expired!
      # Redis TTL handles expiration automatically, but this can be used
      # for additional cleanup if needed
      count = 0
      
      begin
        # Scan for auth_token keys and check if they're expired
        redis.scan_each(match: "#{REDIS_KEY_PREFIX}:*") do |key|
          ttl = redis.ttl(key)
          if ttl == -1 # Key exists but has no TTL set
            redis.del(key)
            count += 1
          end
        end
      rescue Redis::BaseError => e
        Rails.logger.error "[AuthToken] Error during cleanup: #{e.message}"
      end
      
      Rails.logger.info "[AuthToken] Cleaned up #{count} expired tokens" if count > 0
      count
    end
  end
  
  # Save the token to Redis
  # @return [Boolean] True if saved successfully
  def save!
    data = {
      user_id: user_id,
      target_url: target_url,
      ip_address: ip_address,
      user_agent: user_agent,
      created_at: created_at.iso8601,
      used: used
    }
    
    key = self.class.redis_key(token)
    self.class.redis.setex(key, TOKEN_TTL.to_i, data.to_json)
    true
  rescue Redis::BaseError => e
    Rails.logger.error "[AuthToken] Failed to save token: #{e.message}"
    false
  end
  
  # Check if token has been used
  # @return [Boolean] True if token has been used
  def used?
    used == true
  end
  
  # Check if token is expired
  # @return [Boolean] True if token is expired
  def expired?
    return false unless created_at
    
    Time.current > (created_at + TOKEN_TTL)
  end
  
  # Get the associated user
  # @return [User, nil] The user associated with this token
  def user
    @user ||= User.find_by(id: user_id) if user_id
  end
  
  # Validate the token model
  # @raise [ActiveModel::ValidationError] If validation fails
  def validate!
    raise ActiveModel::ValidationError.new(self) unless valid?
  end
  
  # String representation for debugging
  # @return [String] Safe string representation
  def to_s
    "#<AuthToken token=#{token&.first(8)}... user_id=#{user_id} used=#{used}>"
  end
end