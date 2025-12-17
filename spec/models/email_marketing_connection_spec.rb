# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EmailMarketingConnection, type: :model do
  let(:business) { create(:business) }

  describe 'associations' do
    it { is_expected.to belong_to(:business) }
    it { is_expected.to have_many(:sync_logs).class_name('EmailMarketingSyncLog').dependent(:destroy) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:provider) }

    it 'validates uniqueness of provider per business' do
      create(:email_marketing_connection, :mailchimp, business: business)
      duplicate = build(:email_marketing_connection, :mailchimp, business: business)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:business_id]).to include('already has a connection for this provider')
    end

    it 'allows different providers for the same business' do
      create(:email_marketing_connection, :mailchimp, business: business)
      cc_connection = build(:email_marketing_connection, :constant_contact, business: business)
      expect(cc_connection).to be_valid
    end
  end

  describe 'enums' do
    it 'defines provider enum' do
      expect(described_class.providers).to include('mailchimp' => 0, 'constant_contact' => 1)
    end

    it 'defines sync_strategy enum' do
      expect(described_class.sync_strategies).to include('manual' => 0, 'auto_on_change' => 1, 'scheduled' => 2)
    end
  end

  describe 'scopes' do
    let!(:active_mailchimp) { create(:email_marketing_connection, :mailchimp, business: business) }
    let!(:inactive_mailchimp) { create(:email_marketing_connection, :mailchimp, :inactive, business: create(:business)) }
    let!(:active_cc) { create(:email_marketing_connection, :constant_contact, business: create(:business)) }

    describe '.active' do
      it 'returns only active connections' do
        expect(described_class.active).to include(active_mailchimp, active_cc)
        expect(described_class.active).not_to include(inactive_mailchimp)
      end
    end

    describe '.mailchimp_connections' do
      it 'returns only mailchimp connections' do
        expect(described_class.mailchimp_connections).to include(active_mailchimp, inactive_mailchimp)
        expect(described_class.mailchimp_connections).not_to include(active_cc)
      end
    end

    describe '.constant_contact_connections' do
      it 'returns only constant contact connections' do
        expect(described_class.constant_contact_connections).to include(active_cc)
        expect(described_class.constant_contact_connections).not_to include(active_mailchimp)
      end
    end
  end

  describe '#token_expired?' do
    context 'when token_expires_at is nil' do
      let(:connection) { build(:email_marketing_connection, :mailchimp, token_expires_at: nil) }

      it 'returns false' do
        expect(connection.token_expired?).to be false
      end
    end

    context 'when token is expired' do
      let(:connection) { build(:email_marketing_connection, :constant_contact, :expired_token) }

      it 'returns true' do
        expect(connection.token_expired?).to be true
      end
    end

    context 'when token is not expired' do
      let(:connection) { build(:email_marketing_connection, :constant_contact, token_expires_at: 1.hour.from_now) }

      it 'returns false' do
        expect(connection.token_expired?).to be false
      end
    end
  end

  describe '#connected?' do
    context 'when active with valid token' do
      let(:connection) { build(:email_marketing_connection, :mailchimp) }

      it 'returns true' do
        expect(connection.connected?).to be true
      end
    end

    context 'when inactive' do
      let(:connection) { build(:email_marketing_connection, :mailchimp, :inactive) }

      it 'returns false' do
        expect(connection.connected?).to be false
      end
    end

    context 'when token is expired' do
      let(:connection) { build(:email_marketing_connection, :constant_contact, :expired_token) }

      it 'returns false' do
        expect(connection.connected?).to be false
      end
    end
  end

  describe '#provider_name' do
    it 'returns Mailchimp for mailchimp provider' do
      connection = build(:email_marketing_connection, :mailchimp)
      expect(connection.provider_name).to eq('Mailchimp')
    end

    it 'returns Constant Contact for constant_contact provider' do
      connection = build(:email_marketing_connection, :constant_contact)
      expect(connection.provider_name).to eq('Constant Contact')
    end
  end

  describe '#record_sync!' do
    let(:connection) { create(:email_marketing_connection, :mailchimp, business: business, total_contacts_synced: 100) }

    it 'updates last_synced_at and increments total_contacts_synced' do
      freeze_time do
        connection.record_sync!(contacts_synced: 50)

        expect(connection.last_synced_at).to eq(Time.current)
        expect(connection.total_contacts_synced).to eq(150)
      end
    end
  end

  describe '#deactivate!' do
    let(:connection) { create(:email_marketing_connection, :mailchimp, business: business) }

    it 'sets active to false and records reason' do
      connection.deactivate!(reason: 'Token expired')

      expect(connection.active).to be false
      expect(connection.config['deactivation_reason']).to eq('Token expired')
      expect(connection.config['deactivated_at']).to be_present
    end
  end

  describe 'encryption' do
    let(:connection) { create(:email_marketing_connection, :mailchimp, business: business) }

    it 'encrypts access_token' do
      # The token should be encrypted in the database
      raw_value = described_class.connection.execute(
        "SELECT access_token FROM email_marketing_connections WHERE id = #{connection.id}"
      ).first['access_token']

      # Raw value should not equal the decrypted value (it's encrypted)
      expect(raw_value).not_to eq(connection.access_token)
    end
  end
end
