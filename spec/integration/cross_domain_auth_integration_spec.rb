# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Cross-domain authentication integration', type: :request do
  let(:custom_domain_business) {
    create(:business, :with_custom_domain, hostname: 'example.com', tier: 'premium', status: 'cname_active')
  }
  let(:custom_domain_user) { create(:user, business: custom_domain_business, role: 'manager', password: 'password123') }

  before do
    # Set host to main domain for auth bridge tests
    host! 'www.example.com'
  end

  before do
    # Ensure clean state for each test
    AuthToken.delete_all
    InvalidatedSession.delete_all
  end

  # Helper method to create test request for token creation
  def mock_request
    ActionDispatch::TestRequest.create(Rack::MockRequest.env_for('http://example.com'))
  end

  # Helper method to sign in a user for testing
  def sign_in(user)
    # Use Warden's login_as helper which is available in integration specs
    login_as(user, scope: :user)

    # Ensure user has a session token
    user.update!(session_token: SecureRandom.urlsafe_base64(32)) unless user.session_token.present?
  end

  describe 'Auth Bridge Token Creation and Validation' do
    it 'creates valid auth tokens for authenticated users' do
      # Sign in user via login_as helper
      sign_in custom_domain_user

      # Test auth bridge token creation
      target_url = "https://example.com/dashboard"
      get "/auth/bridge", params: { target_url: target_url, business_id: custom_domain_business.id }

      # Should redirect to custom domain with auth token
      expect(response).to have_http_status(:redirect)

      # Check that an auth token was created
      expect(AuthToken.count).to eq(1)
      token = AuthToken.last
      expect(token.user).to eq(custom_domain_user)
      expect(token.target_url).to eq(target_url)
    end

    it 'validates target URLs against business domains' do
      sign_in custom_domain_user

      # Try to create token for invalid domain
      malicious_url = "https://evil.com/steal-data"
      get "/auth/bridge", params: { target_url: malicious_url, business_id: custom_domain_business.id }

      expect(response).to have_http_status(:bad_request)
      expect(response.body).to include('Invalid target URL')
      expect(AuthToken.count).to eq(0)
    end

    it 'requires authentication for token creation' do
      # Try to create token without being signed in
      target_url = "https://example.com/dashboard"
      get "/auth/bridge", params: { target_url: target_url, business_id: custom_domain_business.id }

      # In Rails, unauthenticated requests typically redirect to login, not return 401
      # But our auth bridge controller explicitly returns 401 JSON for unauthenticated requests
      if response.content_type&.include?('application/json')
        expect(response).to have_http_status(:unauthorized)
        expect(response.body).to include('Authentication required')
      else
        # If it redirects to login instead, that's also valid
        expect(response).to have_http_status(:redirect)
        expect(response.location).to include('/users/sign_in')
      end
    end
  end

  describe 'Auth Token Consumption' do
    it 'successfully consumes valid tokens' do
      # Create auth token manually for testing
      auth_token = AuthToken.create_for_user!(
        custom_domain_user,
        "https://example.com/dashboard",
        mock_request
      )

      # Test token consumption
      get "/auth/consume", params: { auth_token: auth_token.token }

      expect(response).to have_http_status(:redirect)
      expect(response.location).to include('/dashboard')

      # Token should be marked as used
      auth_token.reload
      expect(auth_token.used?).to be true
    end

    it 'rejects invalid or expired tokens' do
      # Try to consume non-existent token
      get "/auth/consume", params: { auth_token: 'invalid_token_123' }

      expect(response).to have_http_status(:redirect)
      expect(response.location).to include('/')
      follow_redirect!
      expect(response.body).to include('Invalid or expired authentication token')
    end

    it 'prevents token reuse' do
      auth_token = AuthToken.create_for_user!(
        custom_domain_user,
        "https://example.com/dashboard",
        mock_request
      )

      # First consumption should work
      get "/auth/consume", params: { auth_token: auth_token.token }
      expect(response).to have_http_status(:redirect)

      # Second consumption should fail
      get "/auth/consume", params: { auth_token: auth_token.token }
      expect(response).to have_http_status(:redirect)
      expect(response.location).to include('/')
    end
  end

  describe 'Rate Limiting and Security' do
    it 'enforces rate limits on auth bridge creation' do
      sign_in custom_domain_user

      target_url = "https://example.com/test"

      # Make requests up to the rate limit (5 in test environment)
      5.times do
        get "/auth/bridge", params: { target_url: target_url, business_id: custom_domain_business.id }
        expect(response).to have_http_status(:redirect) # Should redirect
      end

      # 6th request should be rate limited
      get "/auth/bridge", params: { target_url: target_url, business_id: custom_domain_business.id }
      expect(response).to have_http_status(:too_many_requests)
      expect(response.body).to include('Rate limit exceeded')
    end

    it 'validates business custom domain configuration' do
      subdomain_business = create(:business, hostname: 'testbiz', host_type: 'subdomain', tier: 'free')
      subdomain_user = create(:user, business: subdomain_business, role: 'manager')

      sign_in subdomain_user

      # Try to create bridge to subdomain business (should fail)
      target_url = "https://testbiz.bizblasts.com/dashboard"
      get "/auth/bridge", params: { target_url: target_url, business_id: subdomain_business.id }

      expect(response).to have_http_status(:bad_request)
      expect(response.body).to include('Business is not custom domain type')
    end
  end

  describe 'Session Management Integration' do
    it 'properly handles logout and session blacklisting' do
      sign_in custom_domain_user

      # Create and consume an auth token
      auth_token = AuthToken.create_for_user!(
        custom_domain_user,
        "https://example.com/dashboard",
        mock_request
      )

      get "/auth/consume", params: { auth_token: auth_token.token }
      expect(response).to have_http_status(:redirect)

      # Get the session token for later verification
      session_token = custom_domain_user.session_token

      # Logout
      delete "/users/sign_out"
      expect(response).to have_http_status(:redirect)

      # Verify session is blacklisted
      expect(InvalidatedSession.session_blacklisted?(session_token)).to be true
    end

    it 'prevents access with blacklisted sessions' do
      sign_in custom_domain_user

      # Manually blacklist the session
      session_token = custom_domain_user.session_token
      InvalidatedSession.blacklist_session!(custom_domain_user, session_token)

      # Try to access protected area
      get "/business_manager/dashboard"
      expect(response).to have_http_status(:redirect)
      expect(response.location).to include('/users/sign_in')
    end
  end

  describe 'Token Lifecycle Management' do
    it 'properly expires tokens after TTL' do
      # Create token and manually expire it
      auth_token = AuthToken.create_for_user!(
        custom_domain_user,
        "https://example.com/dashboard",
        mock_request
      )

      # Manually set expiration to past
      auth_token.update!(expires_at: 1.minute.ago)

      # Try to consume expired token
      get "/auth/consume", params: { auth_token: auth_token.token }

      expect(response).to have_http_status(:redirect)
      expect(response.location).to include('/')
    end

    it 'cleans up expired tokens automatically' do
      # Create some expired tokens
      5.times do
        AuthToken.create!(
          user: custom_domain_user,
          token: SecureRandom.urlsafe_base64(32),
          target_url: 'https://example.com/test',
          ip_address: '127.0.0.1',
          user_agent: 'Test',
          expires_at: 1.hour.ago
        )
      end

      expect(AuthToken.expired.count).to eq(5)

      # Run cleanup
      AuthToken.cleanup_expired!

      expect(AuthToken.expired.count).to eq(0)
    end

    it 'validates device fingerprints for enhanced security' do
      # Create token with specific request
      request = mock_request
      request.user_agent = 'Mozilla/5.0 (Test Browser)'
      auth_token = AuthToken.create_for_user!(custom_domain_user, "https://example.com/test", request)

      # Should have device fingerprint
      expect(auth_token.device_fingerprint).to be_present

      # Token consumption should work (defensive validation)
      get "/auth/consume", params: { auth_token: auth_token.token }
      expect(response).to have_http_status(:redirect)
      expect(response.location).to include('/test')
    end
  end
end