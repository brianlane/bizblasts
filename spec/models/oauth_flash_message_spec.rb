# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OauthFlashMessage, type: :model do
  describe 'validations' do
    it 'requires a token' do
      message = described_class.new(expires_at: 5.minutes.from_now)
      expect(message).not_to be_valid
      expect(message.errors[:token]).to include("can't be blank")
    end

    it 'requires expires_at' do
      message = described_class.new(token: SecureRandom.urlsafe_base64(32))
      expect(message).not_to be_valid
      expect(message.errors[:expires_at]).to include("can't be blank")
    end

    it 'enforces token uniqueness' do
      token = SecureRandom.urlsafe_base64(32)
      described_class.create!(token: token, expires_at: 5.minutes.from_now)

      duplicate = described_class.new(token: token, expires_at: 5.minutes.from_now)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:token]).to include('has already been taken')
    end
  end

  describe '.create_with_token' do
    it 'creates a record with notice and returns the token' do
      token = described_class.create_with_token(notice: 'Success!')

      expect(token).to be_present
      expect(token.length).to be >= 40 # urlsafe_base64(32) is ~43 chars

      record = described_class.find_by(token: token)
      expect(record).to be_present
      expect(record.notice).to eq('Success!')
      expect(record.alert).to be_nil
      expect(record.used).to be(false)
      expect(record.expires_at).to be_within(10.seconds).of(5.minutes.from_now)
    end

    it 'creates a record with alert' do
      token = described_class.create_with_token(alert: 'Connection failed')

      record = described_class.find_by(token: token)
      expect(record.alert).to eq('Connection failed')
      expect(record.notice).to be_nil
    end

    it 'creates a record with both notice and alert' do
      token = described_class.create_with_token(notice: 'Partial success', alert: 'Some items failed')

      record = described_class.find_by(token: token)
      expect(record.notice).to eq('Partial success')
      expect(record.alert).to eq('Some items failed')
    end
  end

  describe '.consume' do
    let!(:valid_token) do
      described_class.create_with_token(notice: 'Connected!', alert: 'Warning')
    end

    it 'returns the flash data for a valid token' do
      result = described_class.consume(valid_token)

      expect(result).to eq({ notice: 'Connected!', alert: 'Warning' })
    end

    it 'marks the token as used' do
      described_class.consume(valid_token)

      record = described_class.find_by(token: valid_token)
      expect(record.used).to be(true)
    end

    it 'returns only non-nil values' do
      token = described_class.create_with_token(notice: 'Success!')
      result = described_class.consume(token)

      expect(result).to eq({ notice: 'Success!' })
      expect(result).not_to have_key(:alert)
    end

    it 'returns nil for already used token (prevents replay)' do
      described_class.consume(valid_token)
      result = described_class.consume(valid_token)

      expect(result).to be_nil
    end

    it 'returns nil for expired token' do
      record = described_class.find_by(token: valid_token)
      record.update_columns(expires_at: 1.minute.ago)

      result = described_class.consume(valid_token)
      expect(result).to be_nil
    end

    it 'returns nil for non-existent token' do
      result = described_class.consume('nonexistent_token_abc123')
      expect(result).to be_nil
    end

    it 'returns nil for blank token' do
      expect(described_class.consume(nil)).to be_nil
      expect(described_class.consume('')).to be_nil
      expect(described_class.consume('   ')).to be_nil
    end

    it 'handles race conditions atomically' do
      # The update_all with where clause ensures only one consumer wins
      record = described_class.find_by(token: valid_token)

      # Simulate another process marking it as used
      described_class.where(id: record.id).update_all(used: true)

      # Now our consume should fail
      result = described_class.consume(valid_token)
      expect(result).to be_nil
    end
  end

  describe '.cleanup_old_records' do
    it 'deletes used records' do
      used_token = described_class.create_with_token(notice: 'Used')
      described_class.consume(used_token)

      expect { described_class.cleanup_old_records }
        .to change(described_class, :count).by(-1)
    end

    it 'deletes expired records' do
      token = described_class.create_with_token(notice: 'Expired')
      described_class.find_by(token: token).update_columns(expires_at: 1.minute.ago)

      expect { described_class.cleanup_old_records }
        .to change(described_class, :count).by(-1)
    end

    it 'keeps valid unused records' do
      token = described_class.create_with_token(notice: 'Valid')

      expect { described_class.cleanup_old_records }
        .not_to change(described_class, :count)

      expect(described_class.find_by(token: token)).to be_present
    end

    it 'returns the count of deleted records' do
      3.times { |i| described_class.create_with_token(notice: "Msg #{i}") }
      described_class.update_all(used: true)

      deleted_count = described_class.cleanup_old_records
      expect(deleted_count).to eq(3)
    end
  end

  describe 'scopes' do
    describe '.expired' do
      it 'returns only expired records' do
        valid = described_class.create!(token: 'valid', expires_at: 5.minutes.from_now)
        expired = described_class.create!(token: 'expired', expires_at: 1.minute.ago)

        expect(described_class.expired).to include(expired)
        expect(described_class.expired).not_to include(valid)
      end
    end

    describe '.used_or_expired' do
      it 'returns used and expired records' do
        valid = described_class.create!(token: 'valid', expires_at: 5.minutes.from_now, used: false)
        used = described_class.create!(token: 'used', expires_at: 5.minutes.from_now, used: true)
        expired = described_class.create!(token: 'expired', expires_at: 1.minute.ago, used: false)

        results = described_class.used_or_expired
        expect(results).to include(used)
        expect(results).to include(expired)
        expect(results).not_to include(valid)
      end
    end
  end
end
