require 'rails_helper'

RSpec.describe 'Public Payments', type: :request do
  let(:business) { create(:business) }
  let(:tenant_customer) { create(:tenant_customer, business: business) }
  let(:user) { create(:user, :client, email: tenant_customer.email) }
  let(:invoice) { create(:invoice, business: business, tenant_customer: tenant_customer) }

  before do
    host! "#{business.subdomain}.example.com"
    ActsAsTenant.current_tenant = business
    sign_in user
  end

  describe 'GET /payments/new' do
    before do
      allow(StripeService).to receive(:create_payment_intent).and_return({ id: 'pi_123', client_secret: 'secret', payment: build(:payment) })
    end

    it 'returns http success and sets client_secret and publishable_key' do
      get new_tenant_payment_path, params: { invoice_id: invoice.id }
      expect(response).to have_http_status(:success)
      expect(assigns(:client_secret)).to eq('secret')
      expect(assigns(:stripe_publishable_key)).to be_present
    end
  end

  describe 'POST /payments' do
    let(:payment_method_id) { 'pm_123' }

    context 'when successful' do
      before do
        allow(StripeService).to receive(:create_payment_intent)
      end

      it 'redirects to the invoice with success message' do
        post tenant_payments_path, params: { invoice_id: invoice.id, payment_method_id: payment_method_id }
        expect(response).to redirect_to(tenant_invoice_path(invoice))
        follow_redirect!
        expect(response.body).to include('Payment submitted successfully.')
      end
    end

    context 'when Stripe error occurs' do
      before do
        allow(StripeService).to receive(:create_payment_intent).and_raise(Stripe::StripeError.new('error'))
      end

      it 're-renders new with error message' do
        post tenant_payments_path, params: { invoice_id: invoice.id, payment_method_id: payment_method_id }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include('error')
      end
    end
  end
end 