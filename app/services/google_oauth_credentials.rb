# GoogleOauthCredentials provides unified access to Google OAuth credentials
# Handles environment-specific credential selection for both Calendar and Business Profile APIs
class GoogleOauthCredentials
  class << self
    # Get Google OAuth client ID for current environment
    def client_id
      if Rails.env.development? || Rails.env.test?
        ENV['GOOGLE_OAUTH_CLIENT_ID_DEV']
      else
        ENV['GOOGLE_OAUTH_CLIENT_ID']
      end
    end
    
    # Get Google OAuth client secret for current environment
    def client_secret
      if Rails.env.development? || Rails.env.test?
        ENV['GOOGLE_OAUTH_CLIENT_SECRET_DEV']
      else
        ENV['GOOGLE_OAUTH_CLIENT_SECRET']
      end
    end
    
    # Check if Google OAuth credentials are configured for current environment
    def configured?
      client_id.present? && client_secret.present?
    end
    
    # Get both credentials as a hash
    def credentials
      {
        client_id: client_id,
        client_secret: client_secret
      }
    end
    
    # Get current environment suffix for logging/debugging
    def environment_suffix
      if Rails.env.development? || Rails.env.test?
        '_DEV'
      else
        ''
      end
    end
  end
end