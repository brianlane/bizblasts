require 'rails_helper'

RSpec.describe BookingManager, type: :service do
  describe '.cancel_booking' do
    let(:business) { create(:business, stripe_account_id: 'acct_test_123') }
    let(:service) { create(:service, business: business, price: 40) }
    let(:staff_member) { create(:staff_member, business: business) }
    let(:tenant_customer) { create(:tenant_customer, business: business, stripe_customer_id: 'cus_test_123') }

    let(:booking) do
      create(:booking, :confirmed,
        business: business,
        service: service,
        staff_member: staff_member,
        tenant_customer: tenant_customer
      )
    end

    let!(:invoice) do
      create(:invoice, business: business, tenant_customer: tenant_customer, booking: booking, total_amount: 40.00)
    end

    let!(:payment) do
      create(:payment, business: business, invoice: invoice, tenant_customer: tenant_customer, amount: 40.00)
    end

    let(:stripe_refund) { double('Stripe::Refund', id: 're_123', amount_refunded: (payment.amount * 100).to_i) }

    before do
      allow(StripeService).to receive(:configure_stripe_api_key)
      allow(Stripe::Refund).to receive(:create).and_return(stripe_refund)
    end

    it 'refunds payment and cancels invoice/order' do
      success, error = BookingManager.cancel_booking(booking, 'Client requested', true)
      expect(success).to be true
      expect(error).to be_nil

      payment.reload
      expect(payment).to be_refunded
      expect(payment.refunded_amount).to eq(40.00)

      invoice.reload
      expect(invoice.status).to eq('cancelled')
    end
  end
end 