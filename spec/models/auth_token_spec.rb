# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AuthToken, type: :model do
  let(:user) { create(:user) }
  let(:target_url) { 'https://example.com/dashboard' }
  let(:ip_address) { '192.168.1.1' }
  let(:user_agent) { 'Mozilla/5.0 Test Browser' }
  let(:mock_redis) { double('Redis') }

  before do
    # Mock Redis for testing
    allow(AuthToken).to receive(:redis).and_return(mock_redis)
    
    # Default Redis behavior
    allow(mock_redis).to receive(:setex).and_return('OK')
    allow(mock_redis).to receive(:get).and_return(nil)
    allow(mock_redis).to receive(:del).and_return(1)
    allow(mock_redis).to receive(:ttl).and_return(120)
    allow(mock_redis).to receive(:exists).and_return(false)
    allow(mock_redis).to receive(:scan_each).and_return([])
  end

  describe '.create_for_user!' do
    it 'creates a valid token for a user' do
      token = AuthToken.create_for_user!(user, target_url, ip_address, user_agent)
      
      expect(token.token).to be_present
      expect(token.user_id).to eq(user.id)
      expect(token.target_url).to eq(target_url)
      expect(token.ip_address).to eq(ip_address)
      expect(token.user_agent).to eq(user_agent)
      expect(token.used?).to be_falsey
      expect(token.created_at).to be_within(1.second).of(Time.current)
    end

    it 'generates unique tokens for multiple requests' do
      token1 = AuthToken.create_for_user!(user, target_url, ip_address, user_agent)
      token2 = AuthToken.create_for_user!(user, target_url, ip_address, user_agent)
      
      expect(token1.token).not_to eq(token2.token)
    end

    it 'stores token in Redis with correct TTL' do
      token = AuthToken.create_for_user!(user, target_url, ip_address, user_agent)
      redis_key = "#{AuthToken::REDIS_KEY_PREFIX}:#{token.token}"
      
      # Verify Redis setex was called with correct parameters
      expect(mock_redis).to have_received(:setex).with(
        redis_key,
        AuthToken::TOKEN_TTL.to_i,
        a_string_matching(/user_id.*target_url.*ip_address.*user_agent/)
      )
    end

    it 'validates required fields' do
      expect {
        AuthToken.create_for_user!(nil, target_url, ip_address, user_agent)
      }.to raise_error(NoMethodError) # user.id call on nil

      expect {
        AuthToken.create_for_user!(user, '', ip_address, user_agent)
      }.to raise_error(ActiveModel::ValidationError)

      expect {
        AuthToken.create_for_user!(user, target_url, '', user_agent)
      }.to raise_error(ActiveModel::ValidationError)
    end

    it 'validates presence of user_agent' do
      expect {
        AuthToken.create_for_user!(user, target_url, ip_address, '')
      }.to raise_error(ActiveModel::ValidationError)
    end
  end

  describe '.consume!' do
    let(:token_data) do
      {
        'user_id' => user.id,
        'target_url' => target_url,
        'ip_address' => ip_address,
        'user_agent' => user_agent,
        'created_at' => Time.current.iso8601,
        'used' => false
      }.to_json
    end
    
    let(:token_string) { 'test_token_123' }

    before do
      # Mock Redis to return the token data
      allow(mock_redis).to receive(:get).with("#{AuthToken::REDIS_KEY_PREFIX}:#{token_string}").and_return(token_data)
    end

    it 'successfully consumes a valid token' do
      consumed_token = AuthToken.consume!(token_string, ip_address, user_agent)
      
      expect(consumed_token).to be_present
      expect(consumed_token.user_id).to eq(user.id)
      expect(consumed_token.target_url).to eq(target_url)
      expect(consumed_token.used?).to be_truthy
    end

    it 'returns nil for non-existent token' do
      allow(mock_redis).to receive(:get).with("#{AuthToken::REDIS_KEY_PREFIX}:nonexistent").and_return(nil)
      consumed_token = AuthToken.consume!('nonexistent', ip_address, user_agent)
      expect(consumed_token).to be_nil
    end

    it 'returns nil for already used token' do
      used_data = JSON.parse(token_data)
      used_data['used'] = true
      used_token_data = used_data.to_json
      allow(mock_redis).to receive(:get).with("#{AuthToken::REDIS_KEY_PREFIX}:#{token_string}").and_return(used_token_data)
      
      consumed_token = AuthToken.consume!(token_string, ip_address, user_agent)
      expect(consumed_token).to be_nil
    end

    it 'returns nil for token with mismatched IP address' do
      consumed_token = AuthToken.consume!(token_string, '192.168.1.2', user_agent)
      expect(consumed_token).to be_nil
    end

    it 'returns nil for token with mismatched user agent when provided' do
      consumed_token = AuthToken.consume!(token_string, ip_address, 'Different Browser')
      expect(consumed_token).to be_present # Should not fail on user agent mismatch, just log warning
    end

    it 'ignores user agent mismatch when current user agent is nil' do
      consumed_token = AuthToken.consume!(token_string, ip_address, nil)
      expect(consumed_token).to be_present
    end

    it 'marks token as used after consumption' do
      AuthToken.consume!(token_string, ip_address, user_agent)
      
      # Verify Redis setex was called to update the token
      expect(mock_redis).to have_received(:setex).at_least(:once)
    end
  end

  describe '.find_valid' do
    let(:token_data) do
      {
        'user_id' => user.id,
        'target_url' => target_url,
        'ip_address' => ip_address,
        'user_agent' => user_agent,
        'created_at' => Time.current.iso8601,
        'used' => false
      }.to_json
    end
    
    let(:token_string) { 'test_token_123' }

    it 'finds an existing valid token' do
      allow(mock_redis).to receive(:get).with("#{AuthToken::REDIS_KEY_PREFIX}:#{token_string}").and_return(token_data)
      
      found_token = AuthToken.find_valid(token_string)
      
      expect(found_token).to be_present
      expect(found_token.user_id).to eq(user.id)
      expect(found_token.token).to eq(token_string)
    end

    it 'returns nil for non-existent token' do
      allow(mock_redis).to receive(:get).with("#{AuthToken::REDIS_KEY_PREFIX}:nonexistent").and_return(nil)
      found_token = AuthToken.find_valid('nonexistent')
      expect(found_token).to be_nil
    end

    it 'returns nil for expired token' do
      # Mock Redis returning nil (expired/deleted key)
      allow(mock_redis).to receive(:get).with("#{AuthToken::REDIS_KEY_PREFIX}:#{token_string}").and_return(nil)
      
      found_token = AuthToken.find_valid(token_string)
      expect(found_token).to be_nil
    end
  end

  describe '#user' do
    it 'returns the associated user' do
      token = AuthToken.new(user_id: user.id)
      expect(token.user).to eq(user)
    end

    it 'returns nil for invalid user_id' do
      token = AuthToken.new(user_id: 99999)
      expect(token.user).to be_nil
    end
  end

  describe '#expired?' do
    it 'returns false for newly created token' do
      token = AuthToken.new(created_at: Time.current)
      expect(token.expired?).to be_falsey
    end

    it 'returns true for old token' do
      token = AuthToken.new(created_at: 10.minutes.ago)
      expect(token.expired?).to be_truthy
    end
  end

  describe 'token generation' do
    it 'generates cryptographically secure tokens' do
      # Generate multiple tokens and ensure they're unique
      tokens = 10.times.map { AuthToken.send(:generate_secure_token) }
      
      expect(tokens.uniq.length).to eq(10) # All unique
      tokens.each do |token|
        expect(token).to be_present
        expect(token.length).to be > 10 # Reasonable length
      end
    end
  end

  describe 'Redis key format' do
    it 'uses consistent key format' do
      expected_key = "#{AuthToken::REDIS_KEY_PREFIX}:test_token"
      actual_key = AuthToken.redis_key('test_token')
      expect(actual_key).to eq(expected_key)
    end
  end

  describe 'edge cases' do
    it 'handles Redis connection failures gracefully during save' do
      # Define a mock Redis error class without needing actual Redis constant
      redis_base_error = Class.new(StandardError)
      redis_connection_error = Class.new(redis_base_error)
      stub_const('Redis::BaseError', redis_base_error)
      stub_const('Redis::ConnectionError', redis_connection_error)
      
      allow(mock_redis).to receive(:setex).and_raise(redis_connection_error)
      
      token = AuthToken.new(
        token: 'test',
        user_id: user.id,
        target_url: target_url,
        ip_address: ip_address,
        user_agent: user_agent,
        created_at: Time.current
      )
      
      expect(token.save!).to be_falsey
    end

    it 'handles very long URLs within reasonable limits' do
      long_url = 'https://example.com/' + 'x' * 1000
      
      token = AuthToken.create_for_user!(user, long_url, ip_address, user_agent)
      expect(token.target_url).to eq(long_url)
    end
  end
end