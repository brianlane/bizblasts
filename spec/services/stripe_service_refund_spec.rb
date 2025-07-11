require 'rails_helper'

RSpec.describe StripeService, type: :service do
  describe '.handle_refund' do
    let(:business) { create(:business, stripe_account_id: 'acct_test_123') }
    let(:tenant_customer) { create(:tenant_customer, business: business, stripe_customer_id: 'cus_test_123') }
    let(:invoice) { create(:invoice, business: business, tenant_customer: tenant_customer, total_amount: 15.00) }
    let!(:payment) do
      create(:payment,
        business: business,
        invoice: invoice,
        tenant_customer: tenant_customer,
        amount: 15.00,
        stripe_charge_id: 'ch_test_123',
        stripe_payment_intent_id: 'pi_test_123'
      )
    end

    let(:charge_event) do
      {
        'id' => 'ch_test_123',
        'amount_refunded' => 1500,
        'refunds' => {
          'data' => [ { 'reason' => 'requested_by_customer' } ]
        }
      }
    end

    it 'marks payment and invoice/order as refunded/cancelled' do
      StripeService.handle_refund(charge_event)

      payment.reload
      expect(payment).to be_refunded
      expect(payment.refunded_amount).to eq(15.0)
      expect(payment.refund_reason).to eq('requested_by_customer')

      invoice.reload
      expect(invoice.status).to eq('cancelled')
    end
  end
end 