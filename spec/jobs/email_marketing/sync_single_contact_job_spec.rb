# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EmailMarketing::SyncSingleContactJob, type: :job do
  include ActiveJob::TestHelper

  let(:business) { create(:business) }
  let!(:connection) { create(:email_marketing_connection, :mailchimp, :with_list, :sync_enabled, business: business) }
  let(:customer) { create(:tenant_customer, business: business, skip_email_marketing_sync: true) }

  describe '#perform' do
    context 'when syncing a customer' do
      it 'calls the sync service for the specified provider' do
        sync_service = instance_double(EmailMarketing::Mailchimp::ContactSyncService)
        allow(EmailMarketing::Mailchimp::ContactSyncService).to receive(:new).and_return(sync_service)
        allow(sync_service).to receive(:sync_customer).and_return({ success: true, action: 'created' })

        expect(sync_service).to receive(:sync_customer).with(customer)
        described_class.new.perform(customer.id, 'mailchimp', 'sync')
      end

      it 'calls the sync service for all providers when provider is nil' do
        sync_service = instance_double(EmailMarketing::Mailchimp::ContactSyncService)
        allow(EmailMarketing::Mailchimp::ContactSyncService).to receive(:new).and_return(sync_service)
        allow(sync_service).to receive(:sync_customer).and_return({ success: true, action: 'created' })

        expect(sync_service).to receive(:sync_customer).with(customer)
        described_class.new.perform(customer.id, nil, 'sync')
      end

      it 'removes contact when action is remove' do
        sync_service = instance_double(EmailMarketing::Mailchimp::ContactSyncService)
        allow(EmailMarketing::Mailchimp::ContactSyncService).to receive(:new).and_return(sync_service)
        allow(sync_service).to receive(:remove_customer).and_return({ success: true, action: 'removed' })

        expect(sync_service).to receive(:remove_customer).with(customer)
        described_class.new.perform(customer.id, 'mailchimp', 'remove')
      end
    end

    context 'when customer does not exist' do
      it 'discards the job' do
        expect {
          perform_enqueued_jobs do
            described_class.perform_later(99999, 'mailchimp', 'sync')
          end
        }.not_to raise_error
      end
    end
  end
end
