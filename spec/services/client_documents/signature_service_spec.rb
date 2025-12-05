# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ClientDocuments::SignatureService, type: :service do
  let(:business) { create(:business) }
  let(:customer) { create(:tenant_customer, business: business) }
  let(:estimate) { create(:estimate, business: business, tenant_customer: customer) }
  let(:document) do
    ClientDocument.create!(
      business: business,
      tenant_customer: customer,
      documentable: estimate,
      document_type: 'estimate',
      status: 'pending_signature'
    )
  end

  before do
    ActsAsTenant.current_tenant = business
  end

  after do
    ActsAsTenant.current_tenant = nil
  end

  it 'captures a signature' do
    service = described_class.new(document)

    signature = service.capture!(
      signer_name: 'John Doe',
      signer_email: 'john@example.com',
      signature_data: 'data:image/png;base64,AAA'
    )

    expect(signature).to be_persisted
    expect(document.reload.signed_at).to be_present
    expect(document.document_signatures.count).to eq(1)
  end
end
