# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EmailMarketing::SyncContactsJob, type: :job do
  include ActiveJob::TestHelper

  let(:business) { create(:business) }
  let(:connection) { create(:email_marketing_connection, :mailchimp, :with_list, :sync_enabled, business: business) }

  describe '#perform' do
    context 'when connection exists and is active' do
      let!(:customers) { create_list(:tenant_customer, 3, business: business) }
      let(:sync_service) { instance_double(EmailMarketing::Mailchimp::ContactSyncService) }

      before do
        allow(EmailMarketingConnection).to receive(:find_by).with(id: connection.id).and_return(connection)
        allow(connection).to receive(:connected?).and_return(true)
        allow(connection).to receive(:sync_service).and_return(sync_service)
        allow(sync_service).to receive(:sync_all).and_return({ success: true, synced: 3, failed: 0 })
        allow(sync_service).to receive(:sync_incremental).and_return({ success: true, synced: 3, failed: 0 })
      end

      it 'performs a full sync when sync_type is full' do
        expect(sync_service).to receive(:sync_all)
        described_class.new.perform(connection.id, { sync_type: 'full' })
      end

      it 'performs an incremental sync by default' do
        expect(sync_service).to receive(:sync_incremental)
        described_class.new.perform(connection.id, {})
      end
    end

    context 'when connection does not exist' do
      it 'does not raise an error' do
        expect {
          perform_enqueued_jobs do
            described_class.perform_later(99999, {})
          end
        }.not_to raise_error
      end
    end

    context 'when connection is inactive' do
      let(:inactive_connection) { create(:email_marketing_connection, :mailchimp, :inactive, business: business) }

      it 'does not perform sync' do
        expect_any_instance_of(EmailMarketing::Mailchimp::ContactSyncService).not_to receive(:sync_all)

        perform_enqueued_jobs do
          described_class.perform_later(inactive_connection.id, { sync_type: 'full' })
        end
      end
    end
  end

  describe 'queue' do
    it 'uses the email_marketing queue' do
      expect(described_class.new.queue_name).to eq('email_marketing')
    end
  end
end
