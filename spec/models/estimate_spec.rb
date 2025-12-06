require 'rails_helper'

RSpec.describe Estimate, type: :model do
  describe '#calculate_totals' do
    it 'calculates subtotal, taxes, and total correctly' do
      estimate = build(:estimate)
      item1 = build(:estimate_item, estimate: estimate, qty: 2, cost_rate: '10.00', tax_rate: '5.0')
      item2 = build(:estimate_item, estimate: estimate, qty: 1, cost_rate: '20.00', tax_rate: '10.0')
      estimate.estimate_items = [item1, item2]
      estimate.valid?

      expect(estimate.subtotal).to eq(40.0)
      # item1 tax_amount = (10 * 2) * 0.05 = 1.0; item2 = (20 * 1) * 0.10 = 2.0; sum=3.0
      expect(estimate.taxes).to eq(3.0)
      expect(estimate.total).to eq(43.0)
    end

    it 'excludes items marked for destruction from totals calculation' do
      estimate = build(:estimate)
      item1 = build(:estimate_item, estimate: estimate, qty: 2, cost_rate: '10.00', tax_rate: '5.0')
      item2 = build(:estimate_item, estimate: estimate, qty: 1, cost_rate: '20.00', tax_rate: '10.0')
      estimate.estimate_items = [item1, item2]

      # Mark item2 for destruction (simulating form submission with _destroy: '1')
      item2.mark_for_destruction

      estimate.valid?

      # Only item1 should be included: subtotal = 2 * 10 = 20.0
      expect(estimate.subtotal).to eq(20.0)
      # Only item1 tax: (10 * 2) * 0.05 = 1.0
      expect(estimate.taxes).to eq(1.0)
      expect(estimate.total).to eq(21.0)
    end

    it 'returns early when all items are marked for destruction' do
      estimate = build(:estimate)
      item1 = build(:estimate_item, estimate: estimate, qty: 2, cost_rate: '10.00', tax_rate: '5.0')
      estimate.estimate_items = [item1]
      item1.mark_for_destruction

      estimate.valid?

      # Totals should remain at 0 when no valid items exist
      expect(estimate.subtotal).to eq(0.0)
      expect(estimate.taxes).to eq(0.0)
      expect(estimate.total).to eq(0.0)
    end
  end

  describe 'customer validation' do
    it 'skips contact validations when tenant_customer_id is present' do
      estimate = build(:estimate, tenant_customer_id: 1, first_name: '', last_name: '', email: '', phone: '', address: '', city: '', state: '', zip: '')
      expect(estimate).to be_valid
    end
  end

  describe '#ensure_client_document!' do
    let(:business) { create(:business) }
    let(:customer) { create(:tenant_customer, business: business) }

    it 'creates a client document and applies the latest template' do
      template = create(:document_template, business: business, document_type: 'estimate', body: '<p>Estimate Terms</p>')
      estimate = create(:estimate, business: business, tenant_customer: customer, required_deposit: 50, total: 200)

      ActsAsTenant.current_tenant = business
      document = estimate.ensure_client_document!

      expect(document).to be_persisted
      expect(document.document_template).to eq(template)
      expect(document.body).to include('Estimate Terms')
      expect(document.metadata['template_version']).to eq(template.version)
      expect(document.deposit_amount.to_f).to eq(50.0)
    ensure
      ActsAsTenant.current_tenant = nil
    end
  end

  describe '#handle_client_document_payment' do
    let(:business) { create(:business) }
    let(:customer) { create(:tenant_customer, business: business) }
    let(:estimate) do
      create(
        :estimate,
        :pending_payment,
        business: business,
        tenant_customer: customer,
        required_deposit: 50,
        total: 200
      )
    end
    let(:document) do
      create(
        :client_document,
        business: business,
        tenant_customer: customer,
        documentable: estimate,
        status: 'pending_payment',
        document_type: 'estimate',
        deposit_amount: 50,
        payment_intent_id: 'pi_123'
      )
    end
    let(:payment) { instance_double(Payment, stripe_payment_intent_id: 'pi_123') }
    let(:mailer_double) { double(deliver_later: true) }

    before do
      allow(EstimateMailer).to receive(:deposit_paid_confirmation).and_return(mailer_double)
      allow(EstimateMailer).to receive(:estimate_approved).and_return(mailer_double)
    end

    it 'approves the estimate once and ignores duplicate webhook deliveries' do
      expect(estimate.handle_client_document_payment(document, payment)).to be_truthy
      expect(estimate.reload).to be_approved

      expect(estimate.handle_client_document_payment(document, payment)).to be_falsey
      expect(EstimateMailer).to have_received(:deposit_paid_confirmation).once
      expect(EstimateMailer).to have_received(:estimate_approved).once
    end
  end
end
