# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AuthToken, type: :model do
  let(:user) { create(:user) }
  let(:target_url) { 'https://example.com/dashboard' }
  let(:ip_address) { '192.168.1.1' }
  let(:user_agent) { 'Mozilla/5.0 Test Browser' }

  describe 'associations' do
    it { should belong_to(:user) }
  end

  describe 'validations' do
    subject { build(:auth_token) }
    
    it { should validate_presence_of(:target_url) }
    it { should validate_presence_of(:ip_address) }
    it { should validate_presence_of(:user_agent) }
    it 'validates uniqueness of token' do
      token1 = create(:auth_token)
      token2 = build(:auth_token, token: token1.token)
      
      expect(token2).not_to be_valid
      expect(token2.errors[:token]).to include('has already been taken')
    end
    
    # Custom validation tests since shoulda-matchers has issues with callbacks
    it 'validates presence of token' do
      token = build(:auth_token, token: nil)
      token.save
      expect(token.token).to be_present  # Should be set by callback
    end
    
    it 'validates presence of expires_at' do
      token = build(:auth_token, expires_at: nil)
      token.save
      expect(token.expires_at).to be_present  # Should be set by callback
    end
  end

  describe 'scopes' do
    let!(:valid_token) { create(:auth_token, used: false, expires_at: 1.hour.from_now) }
    let!(:used_token) { create(:auth_token, used: true, expires_at: 1.hour.from_now) }
    let!(:expired_token) { create(:auth_token, used: false, expires_at: 1.hour.ago) }

    describe '.valid' do
      it 'returns only unused and non-expired tokens' do
        expect(AuthToken.valid).to include(valid_token)
        expect(AuthToken.valid).not_to include(used_token)
        expect(AuthToken.valid).not_to include(expired_token)
      end
    end

    describe '.expired' do
      it 'returns only expired tokens' do
        expect(AuthToken.expired).to include(expired_token)
        expect(AuthToken.expired).not_to include(valid_token)
        expect(AuthToken.expired).not_to include(used_token)
      end
    end
  end

  describe '.create_for_user!' do
    let(:mock_request) { double('request', remote_ip: ip_address, user_agent: user_agent) }
    
    it 'creates a valid token for a user' do
      token = AuthToken.create_for_user!(user, target_url, mock_request)
      
      expect(token.token).to be_present
      expect(token.user_id).to eq(user.id)
      expect(token.target_url).to eq(target_url)
      expect(token.ip_address).to eq(ip_address)
      expect(token.user_agent).to eq(user_agent)
      expect(token.used?).to be_falsey
      expect(token.expires_at).to be_within(1.second).of(AuthToken::TOKEN_TTL.call.from_now)
      expect(token.persisted?).to be_truthy
    end

    it 'generates unique tokens for multiple requests' do
      token1 = AuthToken.create_for_user!(user, target_url, mock_request)
      token2 = AuthToken.create_for_user!(user, target_url, mock_request)
      
      expect(token1.token).not_to eq(token2.token)
    end

    it 'validates required fields' do
      expect {
        AuthToken.create_for_user!(nil, target_url, mock_request)
      }.to raise_error(ActiveRecord::RecordInvalid, /User must exist/)

      expect {
        AuthToken.create_for_user!(user, '', mock_request)
      }.to raise_error(ActiveRecord::RecordInvalid, /Target url can't be blank/)

      blank_ip_request = double('request', remote_ip: '', user_agent: user_agent)
      expect {
        AuthToken.create_for_user!(user, target_url, blank_ip_request)
      }.to raise_error(ActiveRecord::RecordInvalid, /Ip address can't be blank/)

      blank_ua_request = double('request', remote_ip: ip_address, user_agent: '')
      expect {
        AuthToken.create_for_user!(user, target_url, blank_ua_request)
      }.to raise_error(ActiveRecord::RecordInvalid, /User agent can't be blank/)
    end
  end

  describe '.find_valid' do
    let!(:valid_token) { create(:auth_token, used: false, expires_at: 1.hour.from_now) }
    let!(:used_token) { create(:auth_token, used: true, expires_at: 1.hour.from_now) }
    let!(:expired_token) { create(:auth_token, used: false, expires_at: 1.hour.ago) }

    it 'returns valid token when found' do
      found_token = AuthToken.find_valid(valid_token.token)
      expect(found_token).to eq(valid_token)
    end

    it 'returns nil for used token' do
      found_token = AuthToken.find_valid(used_token.token)
      expect(found_token).to be_nil
    end

    it 'returns nil for expired token' do
      found_token = AuthToken.find_valid(expired_token.token)
      expect(found_token).to be_nil
    end

    it 'returns nil for non-existent token' do
      found_token = AuthToken.find_valid('nonexistent')
      expect(found_token).to be_nil
    end

    it 'returns nil for blank token' do
      expect(AuthToken.find_valid('')).to be_nil
      expect(AuthToken.find_valid(nil)).to be_nil
    end
  end

  describe '.consume!' do
    let!(:valid_token) { create(:auth_token, user: user, ip_address: ip_address, user_agent: user_agent, used: false, expires_at: 1.hour.from_now) }
    let(:mock_request) { double('request', remote_ip: ip_address, user_agent: user_agent) }

    it 'successfully consumes a valid token' do
      consumed_token = AuthToken.consume!(valid_token.token, mock_request)
      
      expect(consumed_token).to eq(valid_token)
      expect(consumed_token.used?).to be_truthy
      
      # Verify token is marked as used in database
      valid_token.reload
      expect(valid_token.used?).to be_truthy
    end

    it 'returns nil for non-existent token' do
      result = AuthToken.consume!('nonexistent', mock_request)
      expect(result).to be_nil
    end

    it 'returns nil for already used token' do
      valid_token.update!(used: true)
      result = AuthToken.consume!(valid_token.token, mock_request)
      expect(result).to be_nil
    end

    it 'returns nil for expired token' do
      valid_token.update!(expires_at: 1.hour.ago)
      result = AuthToken.consume!(valid_token.token, mock_request)
      expect(result).to be_nil
    end

    it 'returns nil for IP address mismatch when strict matching enabled' do
      allow(SecurityConfig).to receive(:strict_ip_match?).and_return(true)
      different_ip_request = double('request', remote_ip: '192.168.1.2', user_agent: user_agent)
      result = AuthToken.consume!(valid_token.token, different_ip_request)
      expect(result).to be_nil
    end

    it 'allows IP address mismatch when strict matching disabled' do
      allow(SecurityConfig).to receive(:strict_ip_match?).and_return(false)
      expect(Rails.logger).to receive(:debug).with(/Client IP changed.*allowed by security config/)
      
      different_ip_request = double('request', remote_ip: '192.168.1.2', user_agent: user_agent)
      result = AuthToken.consume!(valid_token.token, different_ip_request)
      expect(result).to eq(valid_token)
      expect(result.used?).to be_truthy
    end

    it 'succeeds despite user agent mismatch (logs warning)' do
      expect(Rails.logger).to receive(:warn).with(/User agent mismatch/)
      
      different_ua_request = double('request', remote_ip: ip_address, user_agent: 'Different Browser')
      result = AuthToken.consume!(valid_token.token, different_ua_request)
      expect(result).to eq(valid_token)
      expect(result.used?).to be_truthy
    end

    it 'handles blank token gracefully' do
      expect(AuthToken.consume!('', mock_request)).to be_nil
      expect(AuthToken.consume!(nil, mock_request)).to be_nil
    end
  end

  describe '.cleanup_expired!' do
    let!(:valid_token) { create(:auth_token, expires_at: 1.hour.from_now) }
    let!(:expired_token1) { create(:auth_token, expires_at: 1.hour.ago) }
    let!(:expired_token2) { create(:auth_token, expires_at: 2.hours.ago) }

    it 'removes expired tokens and returns count' do
      expect(AuthToken.count).to eq(3)
      
      count = AuthToken.cleanup_expired!
      
      expect(count).to eq(2)
      expect(AuthToken.count).to eq(1)
      expect(AuthToken.first).to eq(valid_token)
    end

    it 'returns 0 when no expired tokens exist' do
      AuthToken.where(id: [expired_token1.id, expired_token2.id]).delete_all
      
      count = AuthToken.cleanup_expired!
      expect(count).to eq(0)
    end
  end

  describe 'instance methods' do
    let(:token) { create(:auth_token) }

    describe '#expired?' do
      it 'returns false for newly created token' do
        expect(token.expired?).to be_falsey
      end

      it 'returns true for old token' do
        token.update!(expires_at: 1.hour.ago)
        expect(token.expired?).to be_truthy
      end
    end

    describe '#consumable?' do
      it 'returns true for unused, non-expired token' do
        token.update!(used: false, expires_at: 1.hour.from_now)
        expect(token.consumable?).to be_truthy
      end

      it 'returns false for used token' do
        token.update!(used: true, expires_at: 1.hour.from_now)
        expect(token.consumable?).to be_falsey
      end

      it 'returns false for expired token' do
        token.update!(used: false, expires_at: 1.hour.ago)
        expect(token.consumable?).to be_falsey
      end
    end
  end

  describe 'callbacks' do
    it 'automatically sets token on creation' do
      token = AuthToken.new(user: user, target_url: target_url, ip_address: ip_address, user_agent: user_agent)
      expect(token.token).to be_blank
      
      token.save!
      expect(token.token).to be_present
      expect(token.token.length).to be > 20  # Should be a decent length
    end

    it 'automatically sets expires_at on creation' do
      token = AuthToken.new(user: user, target_url: target_url, ip_address: ip_address, user_agent: user_agent)
      expect(token.expires_at).to be_blank
      
      token.save!
      expect(token.expires_at).to be_within(1.second).of(AuthToken::TOKEN_TTL.call.from_now)
    end

    it 'does not override existing token' do
      existing_token = 'existing_token_value'
      token = AuthToken.new(
        user: user, 
        target_url: target_url, 
        ip_address: ip_address, 
        user_agent: user_agent,
        token: existing_token
      )
      
      token.save!
      expect(token.token).to eq(existing_token)
    end
  end

  describe 'token generation' do
    it 'generates cryptographically secure tokens' do
      tokens = 10.times.map { AuthToken.create!(user: user, target_url: target_url, ip_address: ip_address, user_agent: user_agent).token }
      
      # All tokens should be unique
      expect(tokens.uniq.length).to eq(10)
      
      # All tokens should be reasonable length
      tokens.each do |token|
        expect(token.length).to be >= 20
        expect(token).to match(/\A[A-Za-z0-9_-]+\z/) # Base64 URL-safe characters
      end
    end
  end
end