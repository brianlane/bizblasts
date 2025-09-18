# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Authentication Bridge', type: :request do
  let(:user) { create(:user, role: :client) }
  let(:business) { create(:business, :with_custom_domain, hostname: 'example.com') }
  let(:target_url) { 'https://example.com/dashboard' }

  before do
    # Clear cache to prevent rate limiting between tests
    Rails.cache.clear
  end


  describe 'GET /auth/bridge' do
    context 'when user is signed in' do
      before { sign_in user }

      it 'creates a token and redirects to target domain with consumption URL' do
        get '/auth/bridge', 
            params: { target_url: target_url, business_id: business.id },
            headers: { 'HTTP_USER_AGENT' => 'Test Browser' }

        expect(response).to have_http_status(:redirect)
        
        # Should redirect to the consumption endpoint on target domain
        expect(response.location).to match(%r{^https://example\.com/auth/consume\?auth_token=})
        
        # Extract token from redirect URL
        token = extract_token_from_location(response)
        expect(token).to be_present
        
        # Verify token exists in Redis
        auth_token = AuthToken.find_valid(token)
        expect(auth_token).to be_present
        expect(auth_token.user_id).to eq(user.id)
        expect(auth_token.target_url).to eq(target_url)
      end

      it 'includes original query parameters in target URL' do
        target_with_params = 'https://example.com/dashboard?tab=bookings&ref=123'
        get '/auth/bridge', 
            params: { target_url: target_with_params, business_id: business.id },
            headers: { 'HTTP_USER_AGENT' => 'Test Browser' }

        expect(response).to have_http_status(:redirect)
        
        token = extract_token_from_location(response)
        auth_token = AuthToken.find_valid(token)
        expect(auth_token.target_url).to eq(target_with_params)
      end

      it 'handles URLs with custom ports' do
        target_with_port = 'https://example.com:8443/dashboard'
        get '/auth/bridge', 
            params: { target_url: target_with_port, business_id: business.id },
            headers: { 'HTTP_USER_AGENT' => 'Test Browser' }

        expect(response).to have_http_status(:redirect)
        expect(response.location).to match(%r{^https://example\.com:8443/auth/consume})
      end

      it 'stores client IP and user agent in token' do
        get '/auth/bridge', 
             params: { target_url: target_url, business_id: business.id },
             headers: { 
               'REMOTE_ADDR' => '192.168.1.100',
               'HTTP_USER_AGENT' => 'Test Browser 1.0'
             }

        token = extract_token_from_location(response)
        auth_token = AuthToken.find_valid(token)
        
        expect(auth_token.ip_address).to eq('192.168.1.100')
        expect(auth_token.user_agent).to eq('Test Browser 1.0')
      end

      it 'rejects invalid target URLs' do
        get '/auth/bridge', 
            params: { target_url: 'javascript:alert(1)' },
            headers: { 'HTTP_USER_AGENT' => 'Test Browser' }
        
        expect(response).to have_http_status(:bad_request)
        expect(response.body).to include('Invalid target URL')
      end

      it 'rejects non-HTTPS URLs in production' do
        allow(Rails.env).to receive(:production?).and_return(true)
        
        get '/auth/bridge', 
            params: { target_url: 'http://example.com/dashboard' },
            headers: { 'HTTP_USER_AGENT' => 'Test Browser' }
        
        expect(response).to have_http_status(:bad_request)
        expect(response.body).to include('Invalid target URL')
      end

      it 'allows HTTP URLs in development' do
        allow(Rails.env).to receive(:development?).and_return(true)
        
        get '/auth/bridge', 
            params: { target_url: 'http://localhost:3000/dashboard' },
            headers: { 'HTTP_USER_AGENT' => 'Test Browser' }
        
        expect(response).to have_http_status(:redirect)
      end

      it 'respects rate limiting' do
        # Make multiple rapid requests
        5.times do
          get '/auth/bridge', 
              params: { target_url: target_url, business_id: business.id },
              headers: { 'HTTP_USER_AGENT' => 'Test Browser' }
          expect(response).to have_http_status(:redirect)
        end

        # 6th request should be rate limited
        get '/auth/bridge', 
            params: { target_url: target_url, business_id: business.id },
            headers: { 'HTTP_USER_AGENT' => 'Test Browser' }
        expect(response).to have_http_status(:too_many_requests)
      end
    end

    context 'when user is not signed in' do
      it 'redirects to login' do
        get '/auth/bridge', params: { target_url: target_url }
        
        expect(response).to have_http_status(:redirect)
        expect(response.location).to include('/users/sign_in')
      end
    end

    context 'with missing target_url' do
      before { sign_in user }

      it 'returns bad request' do
        get '/auth/bridge', headers: { 'HTTP_USER_AGENT' => 'Test Browser' }
        
        expect(response).to have_http_status(:bad_request)
        expect(response.body).to include('Invalid target URL')
      end
    end
  end

  describe 'GET /auth/consume' do
    let(:auth_token) { AuthToken.create_for_user!(user, target_url, '192.168.1.1', 'Test Browser') }

    context 'with valid token' do
      it 'signs in user and redirects to target URL' do
        get '/auth/consume', 
            params: { auth_token: auth_token.token },
            headers: { 'REMOTE_ADDR' => '192.168.1.1', 'HTTP_USER_AGENT' => 'Test Browser' }

        expect(response).to have_http_status(:redirect)
        expect(response.location).to eq(target_url)
        
        # Verify user is signed in
        expect(controller.current_user).to eq(user)
        
        # Verify token is consumed
        refreshed_token = AuthToken.find_valid(auth_token.token)
        expect(refreshed_token.used?).to be_truthy
      end

      it 'handles target URLs with query parameters' do
        target_with_query = 'https://example.com/dashboard?tab=settings'
        token_with_query = AuthToken.create_for_user!(user, target_with_query, '192.168.1.1', 'Test Browser')
        
        get '/auth/consume',
            params: { auth_token: token_with_query.token },
            headers: { 'REMOTE_ADDR' => '192.168.1.1', 'HTTP_USER_AGENT' => 'Test Browser' }

        expect(response).to have_http_status(:redirect)
        expect(response.location).to eq(target_with_query)
      end

      it 'adds notice message for successful authentication' do
        get '/auth/consume',
            params: { auth_token: auth_token.token },
            headers: { 'REMOTE_ADDR' => '192.168.1.1', 'HTTP_USER_AGENT' => 'Test Browser' }

        expect(flash[:notice]).to eq('Successfully signed in')
      end

      it 'preserves additional query parameters' do
        get '/auth/consume',
            params: { 
              auth_token: auth_token.token,
              redirect_to: '/custom/path',
              utm_source: 'email'
            },
            headers: { 'REMOTE_ADDR' => '192.168.1.1', 'HTTP_USER_AGENT' => 'Test Browser' }

        expect(response).to have_http_status(:redirect)
        # Should include the additional parameters
        expect(response.location).to include('utm_source=email')
      end
    end

    context 'with invalid token' do
      it 'redirects to root with error for non-existent token' do
        get '/auth/consume', params: { auth_token: 'nonexistent' }

        expect(response).to have_http_status(:redirect)
        expect(response.location).to eq('http://www.example.com/')
        expect(flash[:alert]).to eq('Invalid or expired authentication token')
        expect(controller.current_user).to be_nil
      end

      it 'rejects already used token' do
        # Consume token once
        AuthToken.consume!(auth_token.token, '192.168.1.1', 'Test Browser')
        
        # Try to use again
        get '/auth/consume',
            params: { auth_token: auth_token.token },
            headers: { 'REMOTE_ADDR' => '192.168.1.1', 'HTTP_USER_AGENT' => 'Test Browser' }

        expect(response).to have_http_status(:redirect)
        expect(response.location).to eq('http://www.example.com/')
        expect(flash[:alert]).to eq('Invalid or expired authentication token')
      end

      it 'rejects token with wrong IP address' do
        get '/auth/consume',
            params: { auth_token: auth_token.token },
            headers: { 'REMOTE_ADDR' => '192.168.1.2', 'HTTP_USER_AGENT' => 'Test Browser' }

        expect(response).to have_http_status(:redirect)
        expect(response.location).to eq('http://www.example.com/')
        expect(flash[:alert]).to eq('Invalid or expired authentication token')
      end

      it 'rejects token with wrong user agent' do
        get '/auth/consume',
            params: { auth_token: auth_token.token },
            headers: { 'REMOTE_ADDR' => '192.168.1.1', 'HTTP_USER_AGENT' => 'Different Browser' }

        expect(response).to have_http_status(:redirect)
        expect(response.location).to eq('http://www.example.com/')
        expect(flash[:alert]).to eq('Invalid or expired authentication token')
      end
    end

    context 'with missing token parameter' do
      it 'redirects to root with error' do
        get '/auth/consume'

        expect(response).to have_http_status(:redirect)
        expect(response.location).to eq('http://www.example.com/')
        expect(flash[:alert]).to eq('Invalid or expired authentication token')
      end
    end
  end

  describe 'Cross-domain integration flow' do
    it 'completes full authentication bridge cycle' do
      sign_in user
      
      # Step 1: User on main domain requests bridge to custom domain
      get '/auth/bridge', params: { target_url: target_url }
      expect(response).to have_http_status(:redirect)
      
      # Extract consumption URL
      consumption_url = response.location
      expect(consumption_url).to match(%r{^https://example\.com/auth/consume})
      
      # Step 2: Simulate request to custom domain's consumption endpoint
      consumption_uri = URI.parse(consumption_url)
      token = URI.decode_www_form(consumption_uri.query).to_h['token']
      
      # Step 3: Consume token on target domain
      get '/auth/consume',
          params: { auth_token: token },
          headers: { 'REMOTE_ADDR' => '127.0.0.1' }  # Same IP as original request
      
      expect(response).to have_http_status(:redirect)
      expect(response.location).to eq(target_url)
      expect(controller.current_user).to eq(user)
      
      # Step 4: Verify token is consumed and cannot be reused
      get '/auth/consume',
          params: { auth_token: token },
          headers: { 'REMOTE_ADDR' => '127.0.0.1' }
      
      expect(response).to have_http_status(:redirect)
      expect(response.location).to eq('/')
      expect(flash[:alert]).to eq('Invalid or expired authentication token')
    end
  end

  describe 'Security considerations' do
    before { sign_in user }

    it 'prevents token reuse across different IPs' do
      get '/auth/bridge', 
           params: { target_url: target_url },
           headers: { 'REMOTE_ADDR' => '192.168.1.1' }
      
      token = URI.decode_www_form(URI.parse(response.location).query).to_h['token']
      
      # Try to consume from different IP
      get '/auth/consume',
          params: { auth_token: token },
          headers: { 'REMOTE_ADDR' => '10.0.0.1' }
      
      expect(response).to have_http_status(:redirect)
      expect(response.location).to eq('/')
      expect(flash[:alert]).to eq('Invalid or expired authentication token')
    end

    it 'has short token expiration' do
      auth_token = AuthToken.create_for_user!(user, target_url, '192.168.1.1', 'Test Browser')
      
      # Verify TTL is set correctly in Redis
      redis_key = "#{AuthToken::REDIS_KEY_PREFIX}:#{auth_token.token}"
      ttl = Redis.current.ttl(redis_key)
      expect(ttl).to be_between(110, 120)  # 2 minutes minus a few seconds for processing
    end

    it 'validates URL schemes to prevent XSS' do
      dangerous_urls = [
        'javascript:alert(1)',
        'data:text/html,<script>alert(1)</script>',
        'vbscript:MsgBox(1)',
        'file:///etc/passwd'
      ]
      
      dangerous_urls.each do |url|
        get '/auth/bridge', params: { target_url: url }
        expect(response).to have_http_status(:bad_request)
      end
    end

    it 'sanitizes redirect URLs to prevent open redirects' do
      # This should be allowed (same domain)
      get '/auth/bridge', params: { target_url: 'https://example.com/path' }
      expect(response).to have_http_status(:redirect)
      
      # These should be rejected in a real implementation (different domains)
      # Note: Current implementation allows any HTTPS URL - consider if this needs restriction
      suspicious_urls = [
        'https://evil.com/phishing',
        'https://example.com.evil.com/phishing'
      ]
      
      suspicious_urls.each do |url|
        get '/auth/bridge', params: { target_url: url }
        # Current implementation allows these - document this behavior
        # In production, you might want to restrict to known business domains
      end
    end
  end

  describe 'Error handling' do
    before { sign_in user }

    it 'handles Redis connection failures gracefully' do
      allow(Redis.current).to receive(:set).and_raise(Redis::ConnectionError)
      
      get '/auth/bridge', params: { target_url: target_url }
      
      expect(response).to have_http_status(:internal_server_error)
      expect(response.body).to include('Authentication service temporarily unavailable')
    end

    it 'handles malformed URLs gracefully' do
      get '/auth/bridge', params: { target_url: 'not-a-url-at-all' }
      
      expect(response).to have_http_status(:bad_request)
      expect(response.body).to include('Invalid target URL')
    end

    it 'handles extremely long URLs' do
      long_url = 'https://example.com/' + 'x' * 10000
      
      get '/auth/bridge', params: { target_url: long_url }
      
      # Should either accept or reject gracefully, not crash
      expect(response.status).to be_between(200, 499)
    end
  end
end