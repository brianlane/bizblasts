# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InvalidatedSession, type: :model do
  let(:user) { create(:user) }
  let(:session_token) { SecureRandom.urlsafe_base64(32) }

  describe 'validations' do
    it 'requires a user' do
      invalidated_session = build(:invalidated_session, user: nil)
      expect(invalidated_session).not_to be_valid
      expect(invalidated_session.errors[:user]).to include("must exist")
    end

    it 'requires a session_token' do
      invalidated_session = build(:invalidated_session, session_token: nil)
      expect(invalidated_session).not_to be_valid
      expect(invalidated_session.errors[:session_token]).to include("can't be blank")
    end

    it 'requires unique session_token' do
      create(:invalidated_session, session_token: 'unique_token')
      duplicate = build(:invalidated_session, session_token: 'unique_token')

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:session_token]).to include("has already been taken")
    end

    it 'requires invalidated_at' do
      invalidated_session = build(:invalidated_session, invalidated_at: nil)
      expect(invalidated_session).not_to be_valid
      expect(invalidated_session.errors[:invalidated_at]).to include("can't be blank")
    end

    it 'requires expires_at' do
      invalidated_session = build(:invalidated_session, expires_at: nil)
      expect(invalidated_session).not_to be_valid
      expect(invalidated_session.errors[:expires_at]).to include("can't be blank")
    end
  end

  describe 'scopes' do
    let!(:active_session) { create(:invalidated_session, expires_at: 1.hour.from_now) }
    let!(:expired_session) { create(:invalidated_session, expires_at: 1.hour.ago) }

    describe '.active' do
      it 'returns only non-expired sessions' do
        expect(InvalidatedSession.active).to include(active_session)
        expect(InvalidatedSession.active).not_to include(expired_session)
      end
    end

    describe '.expired' do
      it 'returns only expired sessions' do
        expect(InvalidatedSession.expired).to include(expired_session)
        expect(InvalidatedSession.expired).not_to include(active_session)
      end
    end
  end

  describe '.session_blacklisted?' do
    context 'when session token is blacklisted and active' do
      before do
        create(:invalidated_session, session_token: session_token, expires_at: 1.hour.from_now)
      end

      it 'returns true' do
        expect(InvalidatedSession.session_blacklisted?(session_token)).to be true
      end
    end

    context 'when session token is blacklisted but expired' do
      before do
        create(:invalidated_session, session_token: session_token, expires_at: 1.hour.ago)
      end

      it 'returns false' do
        expect(InvalidatedSession.session_blacklisted?(session_token)).to be false
      end
    end

    context 'when session token is not blacklisted' do
      it 'returns false' do
        expect(InvalidatedSession.session_blacklisted?('non_existent_token')).to be false
      end
    end

    context 'when session token is nil or empty' do
      it 'returns false for nil' do
        expect(InvalidatedSession.session_blacklisted?(nil)).to be false
      end

      it 'returns false for empty string' do
        expect(InvalidatedSession.session_blacklisted?('')).to be false
      end
    end
  end

  describe '.blacklist_session!' do
    it 'creates a new invalidated session record' do
      expect {
        InvalidatedSession.blacklist_session!(user, session_token)
      }.to change(InvalidatedSession, :count).by(1)

      invalidated_session = InvalidatedSession.last
      expect(invalidated_session.user).to eq(user)
      expect(invalidated_session.session_token).to eq(session_token)
      expect(invalidated_session.invalidated_at).to be_within(1.second).of(Time.current)
      expect(invalidated_session.expires_at).to be_within(1.second).of(24.hours.from_now)
    end

    it 'accepts custom TTL' do
      InvalidatedSession.blacklist_session!(user, session_token, ttl: 12.hours)

      invalidated_session = InvalidatedSession.last
      expect(invalidated_session.expires_at).to be_within(1.second).of(12.hours.from_now)
    end

    it 'handles duplicate session tokens gracefully' do
      # Create first entry
      InvalidatedSession.blacklist_session!(user, session_token)
      initial_count = InvalidatedSession.count

      # Try to create duplicate - should not raise error or create duplicate
      expect {
        InvalidatedSession.blacklist_session!(user, session_token)
      }.not_to change(InvalidatedSession, :count)

      expect(InvalidatedSession.count).to eq(initial_count)
    end

    it 'does nothing when user is nil' do
      expect {
        InvalidatedSession.blacklist_session!(nil, session_token)
      }.not_to change(InvalidatedSession, :count)
    end

    it 'does nothing when session_token is nil or empty' do
      expect {
        InvalidatedSession.blacklist_session!(user, nil)
      }.not_to change(InvalidatedSession, :count)

      expect {
        InvalidatedSession.blacklist_session!(user, '')
      }.not_to change(InvalidatedSession, :count)
    end
  end

  describe '.cleanup_expired!' do
    let!(:active_sessions) { create_list(:invalidated_session, 3, expires_at: 1.hour.from_now) }
    let!(:expired_sessions) { create_list(:invalidated_session, 2, expires_at: 1.hour.ago) }

    it 'removes only expired sessions' do
      expect {
        InvalidatedSession.cleanup_expired!
      }.to change(InvalidatedSession, :count).by(-2)

      # Check that active sessions remain
      active_sessions.each do |session|
        expect(InvalidatedSession.exists?(session.id)).to be true
      end

      # Check that expired sessions are gone
      expired_sessions.each do |session|
        expect(InvalidatedSession.exists?(session.id)).to be false
      end
    end

    it 'returns count of cleaned up sessions' do
      result = InvalidatedSession.cleanup_expired!
      expect(result).to eq(2)
    end

    it 'returns 0 when no expired sessions exist' do
      InvalidatedSession.expired.delete_all
      result = InvalidatedSession.cleanup_expired!
      expect(result).to eq(0)
    end
  end

  describe '#expired?' do
    it 'returns true when expires_at is in the past' do
      invalidated_session = build(:invalidated_session, expires_at: 1.hour.ago)
      expect(invalidated_session.expired?).to be true
    end

    it 'returns false when expires_at is in the future' do
      invalidated_session = build(:invalidated_session, expires_at: 1.hour.from_now)
      expect(invalidated_session.expired?).to be false
    end

    it 'returns true when expires_at is exactly now' do
      now = Time.current
      allow(Time).to receive(:current).and_return(now)

      invalidated_session = build(:invalidated_session, expires_at: now)
      expect(invalidated_session.expired?).to be true
    end
  end

  describe '#active?' do
    it 'returns false when session is expired' do
      invalidated_session = build(:invalidated_session, expires_at: 1.hour.ago)
      expect(invalidated_session.active?).to be false
    end

    it 'returns true when session is not expired' do
      invalidated_session = build(:invalidated_session, expires_at: 1.hour.from_now)
      expect(invalidated_session.active?).to be true
    end
  end
end
