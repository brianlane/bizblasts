require 'rails_helper'

RSpec.describe Payment, type: :model do
  describe '#initiate_refund' do
    let(:business) { create(:business, stripe_account_id: 'acct_test_123') }
    let(:tenant_customer) { create(:tenant_customer, business: business, stripe_customer_id: 'cus_test_123') }
    let(:invoice) { create(:invoice, business: business, tenant_customer: tenant_customer, total_amount: 25.00) }
    let(:payment) { create(:payment, business: business, invoice: invoice, tenant_customer: tenant_customer, amount: 25.00) }

    let(:stripe_refund) { double('Stripe::Refund', id: 're_123', amount_refunded: (payment.amount * 100).to_i) }

    before do
      allow(StripeService).to receive(:configure_stripe_api_key)
      allow(Stripe::Refund).to receive(:create).and_return(stripe_refund)
    end

    it 'creates a refund via Stripe and updates payment record' do
      expect(Stripe::Refund).to receive(:create).with(
        hash_including(payment_intent: payment.stripe_payment_intent_id),
        { stripe_account: business.stripe_account_id }
      ).and_return(stripe_refund)

      result = payment.initiate_refund(reason: 'requested_by_customer')

      expect(result).to eq(stripe_refund)
      payment.reload
      expect(payment).to be_refunded
      expect(payment.refunded_amount).to eq(25.00)
    end

    it 'adds validation error when payment is not completed' do
      payment.update!(status: :pending)
      result = payment.initiate_refund
      expect(result).to be_falsey
      expect(payment.errors[:base]).to include('Only completed payments can be refunded')
    end
  end
end 