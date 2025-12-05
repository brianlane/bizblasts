# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ClientDocument, type: :model do
  let(:business) { create(:business) }
  let(:customer) { create(:tenant_customer, business: business) }
  let(:estimate) { create(:estimate, business: business, tenant_customer: customer) }

  before do
    ActsAsTenant.current_tenant = business
  end

  after do
    ActsAsTenant.current_tenant = nil
  end

  it 'creates a pending signature document for an estimate' do
    document = described_class.create!(
      business: business,
      tenant_customer: customer,
      documentable: estimate,
      document_type: 'estimate',
      status: 'pending_signature',
      deposit_amount: 50,
      payment_required: true
    )

    expect(document).to be_pending_signature
    expect(document.documentable).to eq(estimate)
  end

  it 'records events' do
    document = described_class.create!(
      business: business,
      tenant_customer: customer,
      documentable: estimate,
      document_type: 'estimate',
      status: 'draft'
    )

    expect { document.record_event!('test', foo: 'bar') }
      .to change { ClientDocumentEvent.count }.by(1)
  end

  it 'applies a document template to populate content' do
    template = create(:document_template, business: business, document_type: 'estimate', body: '<p>Updated terms</p>')
    document = build(
      :client_document,
      business: business,
      tenant_customer: customer,
      documentable: estimate,
      document_type: 'estimate'
    )

    document.apply_template(template)

    expect(document.document_template).to eq(template)
    expect(document.body).to include('Updated terms')
    expect(document.metadata['template_version']).to eq(template.version)
  end
end
