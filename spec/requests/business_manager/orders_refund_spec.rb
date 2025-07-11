require 'rails_helper'

RSpec.describe 'Business Manager Order Refunds', type: :request do
  let(:business) { create(:business, stripe_account_id: 'acct_test_123') }
  let(:manager)  { create(:user, :manager, business: business) }
  let(:tenant_customer) { create(:tenant_customer, business: business, stripe_customer_id: 'cus_test_123') }

  let(:order) do
    create(:order, :paid, business: business, tenant_customer: tenant_customer, order_type: :product, total_amount: 50.0)
  end

  let!(:invoice) do
    create(:invoice, :paid, business: business, tenant_customer: tenant_customer, order: order, total_amount: 50.0)
  end

  let!(:payment) do
    create(:payment, business: business, invoice: invoice, tenant_customer: tenant_customer, amount: 50.0,
           stripe_payment_intent_id: 'pi_test_123', stripe_charge_id: 'ch_test_123')
  end

  let(:stripe_refund) { double('Stripe::Refund', id: 're_123', amount_refunded: 5000) }

  before do
    host! "#{business.hostname}.lvh.me"
    ActsAsTenant.current_tenant = business
    allow(StripeService).to receive(:configure_stripe_api_key)
    allow(Stripe::Refund).to receive(:create).and_return(stripe_refund)
  end

  after { ActsAsTenant.current_tenant = nil }

  describe 'PATCH /manage/orders/:id/refund' do
    context 'as manager' do
      before { sign_in manager }

      it 'initiates refund and returns to order page' do
        patch refund_business_manager_order_path(order)
        expect(response).to redirect_to(business_manager_order_path(order))

        follow_redirect!
        expect(response.body).to include('Refund initiated successfully').or include('Order already refunded')

        payment.reload
        expect(payment).to be_refunded
        expect(order.reload.status).to eq('refunded')
      end
    end

    context 'as unauthenticated user' do
      it 'redirects to login' do
        patch refund_business_manager_order_path(order)
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end
end 