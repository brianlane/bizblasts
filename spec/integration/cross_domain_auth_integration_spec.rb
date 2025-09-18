# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Cross-Domain Authentication Integration', type: :request do
  let(:user) { create(:user, role: :client) }
  let(:custom_domain_business) { create(:business, :with_custom_domain, hostname: 'mycustomdomain.com') }
  let(:subdomain_business) { create(:business, hostname: 'subdomain-biz', host_type: 'subdomain') }

  before do
    Redis.current.flushdb
    # Set up tenant context for the custom domain business
    ActsAsTenant.current_tenant = custom_domain_business
  end

  after do
    ActsAsTenant.current_tenant = nil
  end

  describe 'Full cross-domain authentication flow' do
    context 'when user navigates from main domain to custom domain business' do
      it 'maintains authentication across domains' do
        # Step 1: User signs in on main domain
        sign_in user
        expect(controller.current_user).to eq(user)

        # Step 2: User clicks link to custom domain business (simulated via bridge)
        target_url = 'https://mycustomdomain.com/services'
        
        post '/auth/bridge', params: { target_url: target_url }
        expect(response).to have_http_status(:redirect)
        
        consumption_url = response.location
        expect(consumption_url).to start_with('https://mycustomdomain.com/auth/consume')

        # Step 3: Browser follows redirect to custom domain
        consumption_uri = URI.parse(consumption_url)
        token = URI.decode_www_form(consumption_uri.query).to_h['auth_token']
        
        # Simulate being on the custom domain
        get '/auth/consume',
            params: { token: token },
            headers: { 
              'Host' => 'mycustomdomain.com',
              'REMOTE_ADDR' => '127.0.0.1'
            }

        # Step 4: User should be authenticated and redirected to intended page
        expect(response).to have_http_status(:redirect)
        expect(response.location).to eq(target_url)
        expect(controller.current_user).to eq(user)
        expect(flash[:notice]).to eq('Successfully signed in')

        # Step 5: Subsequent requests to custom domain should maintain authentication
        get '/services', headers: { 'Host' => 'mycustomdomain.com' }
        expect(controller.current_user).to eq(user)
      end

      it 'handles authentication with complex target URLs containing query parameters' do
        sign_in user
        
        complex_target = 'https://mycustomdomain.com/booking/new?service_id=123&staff_id=456&date=2024-01-15'
        
        post '/auth/bridge', params: { target_url: complex_target }
        expect(response).to have_http_status(:redirect)
        
        consumption_url = response.location
        token = URI.decode_www_form(URI.parse(consumption_url).query).to_h['auth_token']
        
        get '/auth/consume',
            params: { token: token },
            headers: { 
              'Host' => 'mycustomdomain.com',
              'REMOTE_ADDR' => '127.0.0.1'
            }

        expect(response).to have_http_status(:redirect)
        expect(response.location).to eq(complex_target)
        expect(controller.current_user).to eq(user)
      end

      it 'preserves additional URL parameters during authentication flow' do
        sign_in user
        
        target_url = 'https://mycustomdomain.com/dashboard'
        
        post '/auth/bridge', params: { target_url: target_url }
        consumption_url = response.location
        token = URI.decode_www_form(URI.parse(consumption_url).query).to_h['auth_token']
        
        # Add additional parameters when consuming token
        get '/auth/consume',
            params: { 
              token: token,
              utm_source: 'email',
              utm_campaign: 'newsletter',
              ref: 'homepage'
            },
            headers: { 
              'Host' => 'mycustomdomain.com',
              'REMOTE_ADDR' => '127.0.0.1'
            }

        expect(response).to have_http_status(:redirect)
        
        # Additional parameters should be preserved in final redirect
        final_url = response.location
        expect(final_url).to include('utm_source=email')
        expect(final_url).to include('utm_campaign=newsletter')
        expect(final_url).to include('ref=homepage')
      end
    end

    context 'when user is already on custom domain' do
      it 'maintains existing authentication without bridge' do
        # Simulate user already authenticated on custom domain
        get '/auth/consume',
            params: { token: 'invalid' },
            headers: { 'Host' => 'mycustomdomain.com' }

        # Should handle gracefully
        expect(response).to have_http_status(:redirect)
        expect(flash[:alert]).to eq('Invalid or expired authentication token')
      end
    end

    context 'with subdomain businesses' do
      it 'does not use bridge for subdomain navigation' do
        sign_in user
        
        # Navigation to subdomain should use normal session sharing
        get '/services', headers: { 'Host' => 'subdomain-biz.lvh.me' }
        
        # Should be authenticated without needing bridge
        expect(controller.current_user).to eq(user)
      end
    end
  end

  describe 'ApplicationController integration' do
    let(:auth_token) { AuthToken.create_for_user!(user, 'https://mycustomdomain.com/dashboard', '127.0.0.1', 'Test Browser') }

    it 'automatically processes auth tokens in incoming requests' do
      # Simulate request to custom domain with auth token
      get '/dashboard',
          params: { auth_token: auth_token.token },
          headers: { 
            'Host' => 'mycustomdomain.com',
            'REMOTE_ADDR' => '127.0.0.1',
            'HTTP_USER_AGENT' => 'Test Browser'
          }

      # Should redirect to clean URL (removing token)
      expect(response).to have_http_status(:redirect)
      expect(response.location).to eq('https://mycustomdomain.com/dashboard')
      
      # Token should be consumed
      refreshed_token = AuthToken.find_valid(auth_token.token)
      expect(refreshed_token.used?).to be_truthy
      
      # Follow the redirect to verify user is signed in
      follow_redirect!
      expect(controller.current_user).to eq(user)
    end

    it 'ignores invalid auth tokens gracefully' do
      get '/dashboard',
          params: { auth_token: 'invalid_token' },
          headers: { 'Host' => 'mycustomdomain.com' }

      # Should not crash, just continue without authentication
      expect(controller.current_user).to be_nil
      expect(response).to have_http_status(:success)
    end

    it 'cleans URLs with consumed tokens' do
      get '/services',
          params: { 
            auth_token: auth_token.token,
            category: 'massage',
            location: 'downtown'
          },
          headers: { 
            'Host' => 'mycustomdomain.com',
            'REMOTE_ADDR' => '127.0.0.1',
            'HTTP_USER_AGENT' => 'Test Browser'
          }

      expect(response).to have_http_status(:redirect)
      
      # Should preserve other parameters but remove auth_token
      cleaned_url = response.location
      expect(cleaned_url).to include('category=massage')
      expect(cleaned_url).to include('location=downtown')
      expect(cleaned_url).not_to include('auth_token')
    end

    it 'handles POST requests with auth tokens' do
      post '/bookings',
           params: { 
             auth_token: auth_token.token,
             booking: { service_id: 1, start_time: Time.current }
           },
           headers: { 
             'Host' => 'mycustomdomain.com',
             'REMOTE_ADDR' => '127.0.0.1',
             'HTTP_USER_AGENT' => 'Test Browser'
           }

      # Should authenticate user for the POST request
      expect(controller.current_user).to eq(user)
      
      # Should not redirect for POST requests, just process normally
      expect(response).to have_http_status(:success)
    end
  end

  describe 'Security edge cases' do
    it 'prevents token replay attacks across different IPs' do
      sign_in user
      
      post '/auth/bridge', 
           params: { target_url: 'https://mycustomdomain.com/dashboard' },
           headers: { 'REMOTE_ADDR' => '192.168.1.1' }
      
      consumption_url = response.location
      token = URI.decode_www_form(URI.parse(consumption_url).query).to_h['auth_token']
      
      # Attempt to use token from different IP
      get '/auth/consume',
          params: { token: token },
          headers: { 
            'Host' => 'mycustomdomain.com',
            'REMOTE_ADDR' => '10.0.0.1'  # Different IP
          }

      expect(response).to have_http_status(:redirect)
      expect(response.location).to eq('/')
      expect(flash[:alert]).to eq('Invalid or expired authentication token')
      expect(controller.current_user).to be_nil
    end

    it 'prevents token hijacking via user agent fingerprinting' do
      sign_in user
      
      post '/auth/bridge',
           params: { target_url: 'https://mycustomdomain.com/dashboard' },
           headers: { 
             'REMOTE_ADDR' => '127.0.0.1',
             'HTTP_USER_AGENT' => 'Mozilla/5.0 Original Browser'
           }
      
      consumption_url = response.location
      token = URI.decode_www_form(URI.parse(consumption_url).query).to_h['auth_token']
      
      # Attempt to use token with different user agent
      get '/auth/consume',
          params: { token: token },
          headers: { 
            'Host' => 'mycustomdomain.com',
            'REMOTE_ADDR' => '127.0.0.1',
            'HTTP_USER_AGENT' => 'Malicious/1.0 Different Browser'
          }

      expect(response).to have_http_status(:redirect)
      expect(response.location).to eq('/')
      expect(flash[:alert]).to eq('Invalid or expired authentication token')
      expect(controller.current_user).to be_nil
    end

    it 'expires tokens automatically after TTL' do
      # Create a token and verify it exists
      auth_token = AuthToken.create_for_user!(user, 'https://mycustomdomain.com/dashboard', '127.0.0.1', 'Test Browser')
      expect(AuthToken.find_valid(auth_token.token)).to be_present
      
      # Simulate token expiration by removing from Redis
      redis_key = "#{AuthToken::REDIS_KEY_PREFIX}:#{auth_token.token}"
      Redis.current.del(redis_key)
      
      # Attempt to consume expired token
      get '/auth/consume',
          params: { token: auth_token.token },
          headers: { 
            'Host' => 'mycustomdomain.com',
            'REMOTE_ADDR' => '127.0.0.1',
            'HTTP_USER_AGENT' => 'Test Browser'
          }

      expect(response).to have_http_status(:redirect)
      expect(response.location).to eq('/')
      expect(flash[:alert]).to eq('Invalid or expired authentication token')
      expect(controller.current_user).to be_nil
    end
  end

  describe 'Rate limiting' do
    it 'prevents excessive bridge requests from same user' do
      sign_in user
      
      # Make multiple requests in quick succession
      5.times do
        post '/auth/bridge', params: { target_url: 'https://mycustomdomain.com/dashboard' }
        expect(response).to have_http_status(:redirect)
      end
      
      # Next request should be rate limited
      post '/auth/bridge', params: { target_url: 'https://mycustomdomain.com/dashboard' }
      expect(response).to have_http_status(:too_many_requests)
    end
  end

  describe 'Business context handling' do
    it 'properly sets tenant context on custom domain' do
      sign_in user
      target_url = 'https://mycustomdomain.com/services'
      
      post '/auth/bridge', params: { target_url: target_url }
      consumption_url = response.location
      token = URI.decode_www_form(URI.parse(consumption_url).query).to_h['auth_token']
      
      get '/auth/consume',
          params: { token: token },
          headers: { 
            'Host' => 'mycustomdomain.com',
            'REMOTE_ADDR' => '127.0.0.1'
          }

      # Should maintain proper tenant context
      expect(ActsAsTenant.current_tenant).to eq(custom_domain_business)
      expect(controller.current_user).to eq(user)
    end
  end
end