# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EmailMarketingSyncLog, type: :model do
  let(:business) { create(:business) }
  let(:connection) { create(:email_marketing_connection, :mailchimp, business: business) }

  describe 'associations' do
    it { is_expected.to belong_to(:business) }
    it { is_expected.to belong_to(:email_marketing_connection) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:sync_type) }
    it { is_expected.to validate_presence_of(:status) }
  end

  describe 'enums' do
    it 'defines sync_type enum' do
      expect(described_class.sync_types).to include(
        'full_sync' => 0,
        'incremental' => 1,
        'single_contact' => 2,
        'batch' => 3
      )
    end

    it 'defines status enum' do
      expect(described_class.statuses).to include(
        'pending' => 0,
        'running' => 1,
        'completed' => 2,
        'failed' => 3,
        'partially_completed' => 4
      )
    end

    it 'defines direction enum' do
      expect(described_class.directions).to include('outbound' => 0, 'inbound' => 1)
    end
  end

  describe '#start!' do
    let(:log) { create(:email_marketing_sync_log, email_marketing_connection: connection, business: business) }

    it 'sets status to running and records start time' do
      freeze_time do
        log.start!

        expect(log.status).to eq('running')
        expect(log.started_at).to eq(Time.current)
      end
    end
  end

  describe '#complete!' do
    let(:log) { create(:email_marketing_sync_log, :running, email_marketing_connection: connection, business: business) }

    context 'when no failures' do
      it 'sets status to completed' do
        log.complete!(total: 50)

        expect(log.status).to eq('completed')
        expect(log.completed_at).to be_present
        expect(log.summary).to include('total' => 50)
      end
    end

    context 'when there are failures' do
      before { log.update!(contacts_failed: 5) }

      it 'sets status to partially_completed' do
        log.complete!(total: 50)

        expect(log.status).to eq('partially_completed')
      end
    end
  end

  describe '#fail!' do
    let(:log) { create(:email_marketing_sync_log, :running, email_marketing_connection: connection, business: business) }

    it 'sets status to failed and records error' do
      log.fail!('API connection timeout')

      expect(log.status).to eq('failed')
      expect(log.completed_at).to be_present
      expect(log.error_details.last['message']).to eq('API connection timeout')
    end
  end

  describe '#increment_synced!' do
    let(:log) { create(:email_marketing_sync_log, email_marketing_connection: connection, business: business, contacts_synced: 10) }

    it 'increments contacts_synced' do
      log.increment_synced!
      expect(log.reload.contacts_synced).to eq(11)
    end
  end

  describe '#duration' do
    context 'when completed' do
      let(:log) do
        create(:email_marketing_sync_log,
               email_marketing_connection: connection,
               business: business,
               started_at: 5.minutes.ago,
               completed_at: Time.current)
      end

      it 'returns the duration in seconds' do
        expect(log.duration).to be_within(1).of(300)
      end
    end

    context 'when not completed' do
      let(:log) { create(:email_marketing_sync_log, email_marketing_connection: connection, business: business) }

      it 'returns nil' do
        expect(log.duration).to be_nil
      end
    end
  end

  describe '#success_rate' do
    context 'when there are synced and failed contacts' do
      let(:log) do
        create(:email_marketing_sync_log,
               email_marketing_connection: connection,
               business: business,
               contacts_synced: 80,
               contacts_failed: 20)
      end

      it 'calculates the percentage' do
        expect(log.success_rate).to eq(80.0)
      end
    end

    context 'when there are no contacts' do
      let(:log) { create(:email_marketing_sync_log, email_marketing_connection: connection, business: business) }

      it 'returns 0' do
        expect(log.success_rate).to eq(0)
      end
    end
  end
end
