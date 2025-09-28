# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AuthenticationTracker, type: :service do
  let(:user) { create(:user) }
  let(:business) { user.business || create(:business) }
  let(:mock_request) do
    mock_session = double('session')
    allow(mock_session).to receive(:id).and_return('session-456')

    instance_double(ActionDispatch::Request,
      user_agent: 'Mozilla/5.0 (Test Browser)',
      host: 'example.com',
      request_id: 'req-123',
      session: mock_session
    )
  end

  before do
    # Enable tracking for tests
    Rails.application.config.x.auth_tracking = ActiveSupport::OrderedOptions.new
    Rails.application.config.x.auth_tracking.enabled = true
    Rails.application.config.x.auth_tracking.monitoring_enabled = false
    Rails.application.config.x.auth_tracking.analytics_enabled = false

    # Mock SecurityConfig.client_ip if it exists, otherwise define a simple mock
    if defined?(SecurityConfig)
      allow(SecurityConfig).to receive(:client_ip).and_return('192.168.1.100')
    else
      stub_const('SecurityConfig', Class.new)
      allow(SecurityConfig).to receive(:client_ip).and_return('192.168.1.100')
    end
  end

  describe '.track_event' do
    context 'when tracking is enabled' do
      it 'tracks a valid event' do
        # Ensure user is created before setting logger expectation
        user_for_test = user
        expect(Rails.logger).to receive(:info).with(/\[AuthTracker\] auth_bridge_created:/)

        result = AuthenticationTracker.track_event(:bridge_created,
          user: user_for_test,
          request: mock_request,
          target_url: 'https://example.com/dashboard'
        )

        expect(result).to be_a(Hash)
        expect(result[:event]).to eq('auth_bridge_created')
        expect(result[:user_id]).to eq(user.id)
        expect(result[:user_role]).to eq(user.role)
        expect(result[:ip_address]).to eq('192.168.1.100')
        expect(result[:host]).to eq('example.com')
        expect(result[:target_url]).to eq('https://example.com/dashboard')
      end

      it 'handles events without user or request' do
        expect(Rails.logger).to receive(:info).with(/\[AuthTracker\] session_blacklisted:/)

        result = AuthenticationTracker.track_event(:session_blacklisted,
          session_token: 'token123',
          reason: 'logout'
        )

        expect(result).to be_a(Hash)
        expect(result[:event]).to eq('session_blacklisted')
        expect(result[:user_id]).to be_nil
        expect(result[:ip_address]).to be_nil
        expect(result[:session_token]).to eq('token123')
        expect(result[:reason]).to eq('logout')
      end

      it 'ignores invalid event types' do
        # Ensure user is created before setting logger expectation
        user_for_test = user
        expect(Rails.logger).not_to receive(:info)

        result = AuthenticationTracker.track_event(:invalid_event_type, user: user_for_test)

        expect(result).to be_nil
      end

      it 'handles tracking errors gracefully' do
        # Ensure user is created before setting logger expectation
        user_for_test = user
        allow(Rails.logger).to receive(:info).and_raise(StandardError.new("Logging error"))
        expect(Rails.logger).to receive(:error).with(/Failed to track event bridge_created: Logging error/)

        result = AuthenticationTracker.track_event(:bridge_created, user: user_for_test)

        expect(result).to be_nil
      end
    end

    context 'when tracking is disabled' do
      before do
        Rails.application.config.x.auth_tracking.enabled = false
      end

      it 'does not track events' do
        # Ensure user is created before setting logger expectation
        user_for_test = user
        expect(Rails.logger).not_to receive(:info)

        result = AuthenticationTracker.track_event(:bridge_created, user: user_for_test)

        expect(result).to be_nil
      end
    end

    context 'when monitoring is enabled' do
      before do
        Rails.application.config.x.auth_tracking.monitoring_enabled = true
      end

      it 'sends to monitoring' do
        # Ensure user is created before setting logger expectation
        user_for_test = user
        expect(Rails.logger).to receive(:info).with(/\[AuthTracker\] auth_bridge_created:/)
        expect(Rails.logger).to receive(:info).with(/\[AuthTracker:Monitor\]/)

        AuthenticationTracker.track_event(:bridge_created, user: user_for_test)
      end
    end

    context 'when analytics is enabled' do
      before do
        Rails.application.config.x.auth_tracking.analytics_enabled = true
      end

      it 'stores for analytics' do
        # Ensure user is created before setting logger expectation
        user_for_test = user
        expect(Rails.logger).to receive(:info).with(/\[AuthTracker\] auth_bridge_created:/)
        expect(Rails.logger).to receive(:info).with(/\[AuthTracker:Analytics\]/)

        AuthenticationTracker.track_event(:bridge_created, user: user_for_test)
      end
    end
  end

  describe '.track_bridge_created' do
    it 'tracks bridge creation with proper data' do
      target_url = 'https://example.com/dashboard?param=value'
      business_id = 123

      expect(AuthenticationTracker).to receive(:track_event).with(:bridge_created,
        user: user,
        request: mock_request,
        target_url: 'https://example.com/dashboard',
        business_id: business_id
      )

      AuthenticationTracker.track_bridge_created(user, target_url, business_id, mock_request)
    end
  end

  describe '.track_bridge_consumed' do
    let(:auth_token) do
      instance_double(AuthToken,
        created_at: 30.seconds.ago,
        target_url: 'https://example.com/dashboard',
        validate_device_fingerprint: true
      )
    end

    it 'tracks bridge consumption with token metrics' do
      expect(AuthenticationTracker).to receive(:track_event).with(:bridge_consumed,
        user: user,
        request: mock_request,
        token_age: be_within(1).of(30),
        target_domain: 'example.com',
        device_fingerprint_match: true
      )

      AuthenticationTracker.track_bridge_consumed(user, auth_token, mock_request)
    end

    it 'handles nil created_at' do
      allow(auth_token).to receive(:created_at).and_return(nil)

      expect(AuthenticationTracker).to receive(:track_event).with(:bridge_consumed,
        user: user,
        request: mock_request,
        token_age: nil,
        target_domain: 'example.com',
        device_fingerprint_match: true
      )

      AuthenticationTracker.track_bridge_consumed(user, auth_token, mock_request)
    end
  end

  describe '.track_bridge_failed' do
    it 'tracks bridge failures with reason' do
      expect(AuthenticationTracker).to receive(:track_event).with(:bridge_failed,
        user: nil,
        request: mock_request,
        failure_reason: 'token_expired',
        token_id: 123
      )

      AuthenticationTracker.track_bridge_failed('token_expired', mock_request, token_id: 123)
    end
  end

  describe '.track_session_created' do
    before do
      user.session_token = 'abcdef1234567890'
    end

    it 'tracks session creation with truncated token' do
      expect(AuthenticationTracker).to receive(:track_event).with(:session_created,
        user: user,
        request: mock_request,
        session_token: 'abcdef12'
      )

      AuthenticationTracker.track_session_created(user, mock_request)
    end

    it 'handles nil session token' do
      user.session_token = nil

      expect(AuthenticationTracker).to receive(:track_event).with(:session_created,
        user: user,
        request: mock_request,
        session_token: nil
      )

      AuthenticationTracker.track_session_created(user, mock_request)
    end
  end

  describe '.track_session_invalidated' do
    it 'tracks session invalidation with truncated token' do
      session_token = 'abcdef1234567890'

      expect(AuthenticationTracker).to receive(:track_event).with(:session_invalidated,
        user: user,
        request: mock_request,
        session_token: 'abcdef12'
      )

      AuthenticationTracker.track_session_invalidated(user, session_token, mock_request)
    end
  end

  describe '.track_session_blacklisted' do
    it 'tracks session blacklisting with reason' do
      session_token = 'abcdef1234567890'

      expect(AuthenticationTracker).to receive(:track_event).with(:session_blacklisted,
        user: user,
        session_token: 'abcdef12',
        reason: 'forced_logout'
      )

      AuthenticationTracker.track_session_blacklisted(user, session_token, 'forced_logout')
    end

    it 'uses default reason when not provided' do
      session_token = 'abcdef1234567890'

      expect(AuthenticationTracker).to receive(:track_event).with(:session_blacklisted,
        user: user,
        session_token: 'abcdef12',
        reason: 'logout'
      )

      AuthenticationTracker.track_session_blacklisted(user, session_token)
    end
  end

  describe '.track_suspicious_request' do
    it 'tracks suspicious requests with reason' do
      expect(AuthenticationTracker).to receive(:track_event).with(:suspicious_request,
        user: user,
        request: mock_request,
        reason: 'rapid_requests'
      )

      AuthenticationTracker.track_suspicious_request(mock_request, 'rapid_requests', user: user)
    end
  end

  describe '.track_device_mismatch' do
    let(:auth_token) do
      instance_double(AuthToken,
        id: 123,
        device_fingerprint: 'expected_fingerprint_123',
        generate_device_fingerprint: 'actual_fingerprint_456'
      )
    end

    it 'tracks device mismatch with fingerprint comparison' do
      expect(AuthenticationTracker).to receive(:track_event).with(:device_mismatch,
        user: user,
        request: mock_request,
        token_id: 123,
        expected_fingerprint: 'expected',
        actual_fingerprint: 'actual_f'
      )

      AuthenticationTracker.track_device_mismatch(user, auth_token, mock_request)
    end
  end

  describe '.track_cross_domain_success' do
    it 'tracks cross-domain authentication success' do
      expect(AuthenticationTracker).to receive(:track_event).with(:cross_domain_success,
        user: user,
        request: mock_request,
        from_domain: 'bizblasts.com',
        to_domain: 'example.com'
      )

      AuthenticationTracker.track_cross_domain_success(user, 'bizblasts.com', 'example.com', mock_request)
    end
  end

  describe 'private methods' do
    describe '#determine_domain_type' do
      context 'in production environment' do
        before do
          allow(Rails).to receive(:env).and_return('production'.inquiry)
        end

        it 'identifies main domain' do
          result = AuthenticationTracker.send(:determine_domain_type, 'bizblasts.com')
          expect(result).to eq('main')
        end

        it 'identifies www main domain' do
          result = AuthenticationTracker.send(:determine_domain_type, 'www.bizblasts.com')
          expect(result).to eq('main')
        end

        it 'identifies subdomain' do
          result = AuthenticationTracker.send(:determine_domain_type, 'test.bizblasts.com')
          expect(result).to eq('subdomain')
        end

        it 'identifies custom domain' do
          result = AuthenticationTracker.send(:determine_domain_type, 'custom-domain.com')
          expect(result).to eq('custom')
        end
      end

      context 'in development/test environment' do
        before do
          allow(Rails).to receive(:env).and_return('development'.inquiry)
        end

        it 'identifies localhost as main' do
          result = AuthenticationTracker.send(:determine_domain_type, 'localhost')
          expect(result).to eq('main')
        end

        it 'identifies lvh.me as main' do
          result = AuthenticationTracker.send(:determine_domain_type, 'lvh.me')
          expect(result).to eq('main')
        end

        it 'identifies lvh.me subdomain' do
          result = AuthenticationTracker.send(:determine_domain_type, 'test.lvh.me')
          expect(result).to eq('subdomain')
        end

        it 'identifies custom domain' do
          result = AuthenticationTracker.send(:determine_domain_type, 'custom-domain.com')
          expect(result).to eq('custom')
        end
      end

      it 'handles nil host' do
        result = AuthenticationTracker.send(:determine_domain_type, nil)
        expect(result).to be_nil
      end
    end

    describe '#sanitize_url' do
      it 'sanitizes URLs properly' do
        url = 'https://example.com/path?param=value#fragment'
        result = AuthenticationTracker.send(:sanitize_url, url)
        expect(result).to eq('https://example.com/path')
      end

      it 'adds default path when missing' do
        url = 'https://example.com'
        result = AuthenticationTracker.send(:sanitize_url, url)
        expect(result).to eq('https://example.com/')
      end

      it 'handles invalid URLs' do
        result = AuthenticationTracker.send(:sanitize_url, 'really-invalid-url-with-no-scheme')
        expect(result).to eq('[invalid_url]')
      end

      it 'handles nil URL' do
        result = AuthenticationTracker.send(:sanitize_url, nil)
        expect(result).to be_nil
      end
    end

    describe '#sanitize_domain' do
      it 'sanitizes domain properly' do
        result = AuthenticationTracker.send(:sanitize_domain, 'EXAMPLE.COM')
        expect(result).to eq('example.com')
      end

      it 'removes invalid characters' do
        result = AuthenticationTracker.send(:sanitize_domain, 'example<script>.com')
        expect(result).to eq('example.com')
      end

      it 'truncates long domains' do
        long_domain = 'a' * 150 + '.com'
        result = AuthenticationTracker.send(:sanitize_domain, long_domain)
        expect(result.length).to eq(100)
      end

      it 'handles nil domain' do
        result = AuthenticationTracker.send(:sanitize_domain, nil)
        expect(result).to be_nil
      end
    end

    describe '#sanitize_user_agent' do
      it 'truncates long user agents' do
        long_ua = 'a' * 300
        result = AuthenticationTracker.send(:sanitize_user_agent, long_ua)
        expect(result.length).to be <= 200
      end

      it 'handles nil user agent' do
        result = AuthenticationTracker.send(:sanitize_user_agent, nil)
        expect(result).to be_nil
      end
    end

    describe '#extract_domain' do
      it 'extracts domain from URL' do
        result = AuthenticationTracker.send(:extract_domain, 'https://example.com/path')
        expect(result).to eq('example.com')
      end

      it 'handles invalid URLs' do
        result = AuthenticationTracker.send(:extract_domain, 'invalid-url')
        expect(result).to be_nil
      end

      it 'handles nil URL' do
        result = AuthenticationTracker.send(:extract_domain, nil)
        expect(result).to be_nil
      end
    end

    describe '#build_event_data' do
      it 'builds complete event data' do
        metadata = { custom_field: 'value' }
        result = AuthenticationTracker.send(:build_event_data, 'test_event', user, mock_request, metadata)

        expect(result[:event]).to eq('test_event')
        expect(result[:user_id]).to eq(user.id)
        expect(result[:user_role]).to eq(user.role)
        expect(result[:ip_address]).to eq('192.168.1.100')
        expect(result[:user_agent]).to eq('Mozilla/5.0 (Test Browser)')
        expect(result[:host]).to eq('example.com')
        expect(result[:request_id]).to eq('req-123')
        expect(result[:custom_field]).to eq('value')
        expect(result[:timestamp]).to be_present
        expect(result[:domain_type]).to be_present
      end

      it 'handles missing user and request' do
        result = AuthenticationTracker.send(:build_event_data, 'test_event', nil, nil, {})

        expect(result[:event]).to eq('test_event')
        expect(result[:timestamp]).to be_present
        expect(result.keys).to contain_exactly(:event, :timestamp)
      end
    end
  end

  describe 'configuration methods' do
    describe '#enabled?' do
      it 'returns true when enabled' do
        Rails.application.config.x.auth_tracking.enabled = true
        expect(AuthenticationTracker.send(:enabled?)).to be true
      end

      it 'returns true when not explicitly disabled' do
        Rails.application.config.x.auth_tracking.enabled = nil
        expect(AuthenticationTracker.send(:enabled?)).to be true
      end

      it 'returns false when explicitly disabled' do
        Rails.application.config.x.auth_tracking.enabled = false
        expect(AuthenticationTracker.send(:enabled?)).to be false
      end
    end

    describe '#monitoring_enabled?' do
      it 'returns true when enabled' do
        Rails.application.config.x.auth_tracking.monitoring_enabled = true
        expect(AuthenticationTracker.send(:monitoring_enabled?)).to be true
      end

      it 'returns false when not enabled' do
        Rails.application.config.x.auth_tracking.monitoring_enabled = false
        expect(AuthenticationTracker.send(:monitoring_enabled?)).to be false
      end
    end

    describe '#analytics_enabled?' do
      it 'returns true when enabled' do
        Rails.application.config.x.auth_tracking.analytics_enabled = true
        expect(AuthenticationTracker.send(:analytics_enabled?)).to be true
      end

      it 'returns false when not enabled' do
        Rails.application.config.x.auth_tracking.analytics_enabled = false
        expect(AuthenticationTracker.send(:analytics_enabled?)).to be false
      end
    end
  end

  describe 'integration with authentication system' do
    let(:auth_token) { create(:auth_token, user: user) }

    it 'provides comprehensive tracking for auth bridge flow' do
      # Track bridge creation
      expect {
        AuthenticationTracker.track_bridge_created(user, 'https://example.com/dashboard', business.id, mock_request)
      }.not_to raise_error

      # Track bridge consumption
      expect {
        AuthenticationTracker.track_bridge_consumed(user, auth_token, mock_request)
      }.not_to raise_error

      # Track session events
      expect {
        AuthenticationTracker.track_session_created(user, mock_request)
        AuthenticationTracker.track_session_invalidated(user, 'token123', mock_request)
        AuthenticationTracker.track_session_blacklisted(user, 'token123', 'logout')
      }.not_to raise_error

      # Track security events
      expect {
        AuthenticationTracker.track_suspicious_request(mock_request, 'rapid_requests', user: user)
        AuthenticationTracker.track_device_mismatch(user, auth_token, mock_request)
      }.not_to raise_error
    end
  end
end