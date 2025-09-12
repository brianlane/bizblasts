require 'rails_helper'

RSpec.describe 'Transactions', type: :request do
  let(:business) { create(:business) }
  let(:tenant_customer) { create(:tenant_customer, business: business) }
  let(:user) { create(:user, :client, email: tenant_customer.email) }
  let(:service) { create(:service, business: business, price: 100.00) }
  let(:staff_member) { create(:staff_member, business: business) }
  let(:booking) { create(:booking, business: business, service: service, staff_member: staff_member, tenant_customer: tenant_customer) }
  let(:invoice) { create(:invoice, :with_booking, business: business, tenant_customer: tenant_customer, booking: booking, status: :pending) }

  before do
    ActsAsTenant.current_tenant = business
    host! host_for(business)
  end

  describe 'GET /transactions/:id (invoice) - Authenticated Users' do
    before { sign_in user }

    it 'displays invoice details with payment button for unpaid invoices' do
      get transaction_path(invoice, type: 'invoice')
      
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(invoice.invoice_number)
      expect(response.body).to include('Payment Required')
      expect(response.body).to include("Pay #{ActionController::Base.helpers.number_to_currency(invoice.balance_due)}")
      expect(response.body).to include('Secure payment powered by Stripe')
    end

    it 'displays paid status for paid invoices' do
      invoice.update!(status: :paid)
      
      get transaction_path(invoice, type: 'invoice')
      
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('This invoice has been paid in full')
      expect(response.body).not_to include('Payment Required')
    end

    it 'displays payment success message when redirected from successful payment' do
      get transaction_path(invoice, type: 'invoice', payment_success: true)
      
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Payment Successful!')
      expect(response.body).to include('Your payment has been processed successfully')
    end

    it 'displays payment cancelled message when redirected from cancelled payment' do
      get transaction_path(invoice, type: 'invoice', payment_cancelled: true)
      
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Payment Cancelled')
      expect(response.body).to include('Your payment was cancelled')
    end

    it 'shows payment history for invoices with payments' do
      payment = create(:payment, 
        invoice: invoice, 
        business: business, 
        tenant_customer: tenant_customer,
        amount: 50.00,
        status: :completed,
        paid_at: 1.day.ago
      )
      
      get transaction_path(invoice, type: 'invoice')
      
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Payment History')
      expect(response.body).to include(ActionController::Base.helpers.number_to_currency(payment.amount))
      expect(response.body).to include('Balance Due')
    end
  end

  describe 'GET /transactions/:id (invoice) - Guest Users' do
    it 'displays invoice details with payment button when valid token provided' do
      get transaction_path(invoice, type: 'invoice', token: invoice.guest_access_token)
      
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(invoice.invoice_number)
      expect(response.body).to include('Payment Required')
      expect(response.body).to include("Pay #{ActionController::Base.helpers.number_to_currency(invoice.balance_due)}")
      expect(response.body).to include('Secure payment powered by Stripe')
    end

    it 'displays paid status for paid invoices with valid token' do
      invoice.update!(status: :paid)
      
      get transaction_path(invoice, type: 'invoice', token: invoice.guest_access_token)
      
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('This invoice has been paid in full')
      expect(response.body).not_to include('Payment Required')
    end

    it 'displays payment success message for guest users' do
      get transaction_path(invoice, type: 'invoice', token: invoice.guest_access_token, payment_success: true)
      
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Payment Successful!')
      expect(response.body).to include('Your payment has been processed successfully')
    end

    it 'displays payment cancelled message for guest users' do
      get transaction_path(invoice, type: 'invoice', token: invoice.guest_access_token, payment_cancelled: true)
      
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Payment Cancelled')
      expect(response.body).to include('Your payment was cancelled')
    end

    it 'redirects to login when no token provided' do
      get transaction_path(invoice, type: 'invoice')

      # The first response should be a redirect (302/303) – eventually we land
      # on the login page that lives on the main domain after the cross-domain
      # auth redirect. Follow redirects until we reach a non-redirect response.
      while response.redirect?
        follow_redirect!
      end

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Please log in to view this transaction')
    end

    it 'returns 404 when invalid token provided' do
      get transaction_path(invoice, type: 'invoice', token: 'invalid_token')
      expect(response).to have_http_status(:not_found)
    end

    it 'shows payment history for guest users with valid token' do
      payment = create(:payment, 
        invoice: invoice, 
        business: business, 
        tenant_customer: tenant_customer,
        amount: 50.00,
        status: :completed,
        paid_at: 1.day.ago
      )
      
      get transaction_path(invoice, type: 'invoice', token: invoice.guest_access_token)
      
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Payment History')
      expect(response.body).to include(ActionController::Base.helpers.number_to_currency(payment.amount))
      expect(response.body).to include('Balance Due')
    end
  end

  describe 'GET /transactions (index) - Authenticated Users' do
    before { sign_in user }
    
    let!(:order) { create(:order, business: business, tenant_customer: tenant_customer) }
    let!(:order_invoice) { create(:invoice, business: business, tenant_customer: tenant_customer, order: order) }

    it 'displays invoices in the transactions list' do
      get transactions_path(filter: 'invoices')
      
      expect(response).to have_http_status(:ok)
      # Check for any invoice number pattern instead of specific numbers
      expect(response.body).to match(/INV-\d{4}-\d{4}/)
      expect(response.body).to include('View Details')
    end

    it 'displays both orders and invoices when filter is both' do
      get transactions_path(filter: 'both')
      
      expect(response).to have_http_status(:ok)
      # Check for invoice and order patterns
      expect(response.body).to match(/INV-\d{4}-\d{4}/)
      expect(response.body).to match(/ORD-[A-F0-9]+/)
    end
  end

  describe 'invoice payment integration' do
    context 'when clicking pay button from transactions view - Authenticated Users' do
      before do
        sign_in user
        allow(StripeService).to receive(:create_payment_checkout_session).and_return({
          session: double('Stripe::Checkout::Session', url: 'https://checkout.stripe.com/pay/cs_test_123')
        })
      end

      it 'redirects to Stripe checkout when payment button is clicked' do
        # First view the invoice in transactions
        get transaction_path(invoice, type: 'invoice')
        expect(response.body).to include("Pay #{ActionController::Base.helpers.number_to_currency(invoice.balance_due)}")
        
        # Then click the payment link (simulate by making the payment request)
        get new_payment_path(invoice_id: invoice.id)
        
        expect(response).to redirect_to('https://checkout.stripe.com/pay/cs_test_123')
        expect(StripeService).to have_received(:create_payment_checkout_session).with(
          invoice: invoice,
          success_url: transaction_url(invoice, type: 'invoice', payment_success: true, host: host_for(business)),
          cancel_url: transaction_url(invoice, type: 'invoice', payment_cancelled: true, host: host_for(business))
        )
      end

      it 'handles payment errors gracefully' do
        allow(StripeService).to receive(:create_payment_checkout_session)
          .and_raise(ArgumentError, "Payment amount must be at least $0.50 USD")

        get new_payment_path(invoice_id: invoice.id)
        
        expect(response).to redirect_to(transaction_path(invoice, type: 'invoice'))
        follow_redirect!
        expect(response.body).to include('This invoice amount is too small for online payment')
      end

      it 'handles Stripe connection errors gracefully' do
        allow(StripeService).to receive(:create_payment_checkout_session)
          .and_raise(Stripe::StripeError.new('Stripe connection error'))

        get new_payment_path(invoice_id: invoice.id)
        
        expect(response).to redirect_to(transaction_path(invoice, type: 'invoice'))
        follow_redirect!
        expect(response.body).to include('Could not connect to Stripe')
      end
    end

    context 'when clicking pay button from transactions view - Guest Users' do
      before do
        allow(StripeService).to receive(:create_payment_checkout_session).and_return({
          session: double('Stripe::Checkout::Session', url: 'https://checkout.stripe.com/pay/cs_guest_123')
        })
      end

      it 'redirects to Stripe checkout for guest users with valid token' do
        # First view the invoice in transactions as guest
        get transaction_path(invoice, type: 'invoice', token: invoice.guest_access_token)
        expect(response.body).to include("Pay #{ActionController::Base.helpers.number_to_currency(invoice.balance_due)}")
        
        # Then click the payment link (simulate by making the payment request)
        get new_payment_path(invoice_id: invoice.id)
        
        expect(response).to redirect_to('https://checkout.stripe.com/pay/cs_guest_123')
        expect(StripeService).to have_received(:create_payment_checkout_session).with(
          invoice: invoice,
          success_url: tenant_invoice_url(invoice, payment_success: true, token: invoice.guest_access_token, host: host_for(business)),
          cancel_url: tenant_invoice_url(invoice, payment_cancelled: true, token: invoice.guest_access_token, host: host_for(business))
        )
      end
    end
  end
end 