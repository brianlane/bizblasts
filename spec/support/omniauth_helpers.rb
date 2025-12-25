# frozen_string_literal: true

# Helper module for OmniAuth testing
module OmniauthHelpers
  # Mock successful Google OAuth authentication
  def mock_google_oauth2(email: 'test@example.com', first_name: 'Test', last_name: 'User', uid: '123456789')
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new({
      provider: 'google_oauth2',
      uid: uid,
      info: {
        email: email,
        first_name: first_name,
        last_name: last_name,
        name: "#{first_name} #{last_name}",
        image: 'https://lh3.googleusercontent.com/a/default-user'
      },
      credentials: {
        token: 'mock_token',
        refresh_token: 'mock_refresh_token',
        expires_at: 1.hour.from_now.to_i,
        expires: true
      },
      extra: {
        raw_info: {
          email: email,
          email_verified: true,
          name: "#{first_name} #{last_name}",
          given_name: first_name,
          family_name: last_name,
          picture: 'https://lh3.googleusercontent.com/a/default-user',
          locale: 'en'
        }
      }
    })
  end

  # Mock OAuth failure
  def mock_google_oauth2_failure(error: :access_denied)
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] = error
  end

  # Reset OmniAuth mock
  def reset_omniauth_mock
    OmniAuth.config.mock_auth[:google_oauth2] = nil
  end

  # Build OmniAuth auth hash directly (for model specs)
  def google_oauth_hash(email: 'test@example.com', first_name: 'Test', last_name: 'User', uid: '123456789')
    OmniAuth::AuthHash.new({
      provider: 'google_oauth2',
      uid: uid,
      info: {
        email: email,
        first_name: first_name,
        last_name: last_name,
        name: "#{first_name} #{last_name}"
      }
    })
  end
end

RSpec.configure do |config|
  config.include OmniauthHelpers

  # Set OmniAuth to test mode before each test
  config.before(:each) do
    OmniAuth.config.test_mode = true
  end

  # Reset OmniAuth mock after each test
  config.after(:each) do
    OmniAuth.config.mock_auth[:google_oauth2] = nil
  end
end

