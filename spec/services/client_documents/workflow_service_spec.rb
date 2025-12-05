# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ClientDocuments::WorkflowService, type: :service do
  let(:business) { create(:business) }
  let(:customer) { create(:tenant_customer, business: business) }
  let(:estimate) { create(:estimate, business: business, tenant_customer: customer) }
  let(:document) do
    ClientDocument.create!(
      business: business,
      tenant_customer: customer,
      documentable: estimate,
      document_type: 'estimate',
      status: 'pending_signature',
      deposit_amount: 50,
      payment_required: true
    )
  end

  before do
    ActsAsTenant.current_tenant = business
  end

  after do
    ActsAsTenant.current_tenant = nil
  end

  it 'transitions to pending payment after signature' do
    service = described_class.new(document)
    service.mark_signature_captured!
    expect(document.reload).to be_pending_payment
  end

  it 'marks payment as received' do
    service = described_class.new(document)
    service.mark_payment_received!(payment_intent_id: 'pi_123', amount_cents: 5000)
    expect(document.reload).to be_completed
    expect(document.payment_intent_id).to eq('pi_123')
  end
end
