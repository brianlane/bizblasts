require 'rails_helper'

RSpec.describe 'Public Payments', type: :request do
  let(:business) { create(:business, subdomain: 'testbiz', hostname: 'testbiz') }
  let(:tenant_customer) { create(:tenant_customer, business: business) }
  let(:user) { create(:user, :client, email: tenant_customer.email) }
  let(:invoice) { create(:invoice, business: business, tenant_customer: tenant_customer, total_amount: 10.00) }

  before do
    host! "#{business.subdomain}.example.com"
    ActsAsTenant.current_tenant = business
  end

  describe 'Authenticated User Payments' do
    before { sign_in user }

    describe 'GET /payments/new' do
      before do
        # Mock the checkout session creation
        allow(StripeService).to receive(:create_payment_checkout_session).and_return({
          session: double('Stripe::Checkout::Session', url: 'https://checkout.stripe.com/pay/cs_test_123')
        })
      end

      it 'redirects to Stripe Checkout for invoice payments' do
        get new_tenant_payment_path, params: { invoice_id: invoice.id }
        expect(response).to redirect_to('https://checkout.stripe.com/pay/cs_test_123')
        expect(StripeService).to have_received(:create_payment_checkout_session).with(
          invoice: invoice,
          success_url: tenant_transaction_url(invoice, type: 'invoice', payment_success: true, host: "#{business.subdomain}.example.com"),
          cancel_url: tenant_transaction_url(invoice, type: 'invoice', payment_cancelled: true, host: "#{business.subdomain}.example.com")
        )
      end

      context 'when invoice amount is too small' do
        before do
          allow(StripeService).to receive(:create_payment_checkout_session)
            .and_raise(ArgumentError, "Payment amount must be at least $0.50 USD")
        end

        it 'redirects to invoice with error message' do
          get new_tenant_payment_path, params: { invoice_id: invoice.id }
          expect(response).to redirect_to(tenant_transaction_path(invoice, type: 'invoice'))
          follow_redirect!
          expect(response).to have_http_status(:ok)
          expect(response.body).to include('This invoice amount is too small for online payment')
        end
      end

      context 'when Stripe error occurs' do
        before do
          allow(StripeService).to receive(:create_payment_checkout_session)
            .and_raise(Stripe::StripeError.new('Stripe connection error'))
        end

        it 'redirects to invoice with error message' do
          get new_tenant_payment_path, params: { invoice_id: invoice.id }
          expect(response).to redirect_to(tenant_transaction_path(invoice, type: 'invoice'))
          follow_redirect!
          expect(response).to have_http_status(:ok)
          expect(response.body).to include('Could not connect to Stripe')
        end
      end
    end

    describe 'POST /payments' do
      it 'redirects to the transaction with message about using payment link' do
        post tenant_payments_path, params: { invoice_id: invoice.id }
        expect(response).to redirect_to(tenant_transaction_path(invoice, type: 'invoice'))
        follow_redirect!
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('Please use the payment link to complete your payment')
      end
    end
  end

  describe 'Guest User Payments' do
    describe 'GET /payments/new' do
      before do
        # Mock the checkout session creation for guest users
        allow(StripeService).to receive(:create_payment_checkout_session).and_return({
          session: double('Stripe::Checkout::Session', url: 'https://checkout.stripe.com/pay/cs_guest_456')
        })
      end

      it 'redirects to Stripe Checkout for guest invoice payments' do
        get new_tenant_payment_path, params: { invoice_id: invoice.id }
        expect(response).to redirect_to('https://checkout.stripe.com/pay/cs_guest_456')
        expect(StripeService).to have_received(:create_payment_checkout_session).with(
          invoice: invoice,
          success_url: tenant_invoice_url(invoice, payment_success: true, token: invoice.guest_access_token, host: "#{business.subdomain}.example.com"),
          cancel_url: tenant_invoice_url(invoice, payment_cancelled: true, token: invoice.guest_access_token, host: "#{business.subdomain}.example.com")
        )
      end

      context 'when invoice amount is too small' do
        before do
          allow(StripeService).to receive(:create_payment_checkout_session)
            .and_raise(ArgumentError, "Payment amount must be at least $0.50 USD")
        end

        it 'redirects to invoice with error message' do
          get new_tenant_payment_path, params: { invoice_id: invoice.id }
          expect(response).to redirect_to(tenant_invoice_path(invoice, token: invoice.guest_access_token))
          follow_redirect!
          expect(response).to have_http_status(:ok)
          expect(response.body).to include('This invoice amount is too small for online payment')
        end
      end

      context 'when Stripe error occurs' do
        before do
          allow(StripeService).to receive(:create_payment_checkout_session)
            .and_raise(Stripe::StripeError.new('Stripe connection error'))
        end

        it 'redirects to invoice with error message' do
          get new_tenant_payment_path, params: { invoice_id: invoice.id }
          expect(response).to redirect_to(tenant_invoice_path(invoice, token: invoice.guest_access_token))
          follow_redirect!
          expect(response).to have_http_status(:ok)
          expect(response.body).to include('Could not connect to Stripe')
        end
      end
    end

    describe 'POST /payments' do
      it 'redirects to the invoice with message about using payment link' do
        post tenant_payments_path, params: { invoice_id: invoice.id }
        expect(response).to redirect_to(tenant_invoice_path(invoice, token: invoice.guest_access_token))
        follow_redirect!
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('Please use the payment link to complete your payment')
      end
    end
  end
end 