require 'rails_helper'

RSpec.describe StripeService, type: :service do
  let(:business) { create(:business, stripe_account_id: 'acct_test123') }
  let(:tenant_customer) { create(:tenant_customer, business: business, stripe_customer_id: 'cus_test123') }
  let(:invoice) { create(:invoice, business: business, tenant_customer: tenant_customer, total_amount: 10.00) }

  before do
    allow(StripeService).to receive(:configure_stripe_api_key)
  end

  describe '.calculate_stripe_fee_cents' do
    it 'calculates 3% plus 30¢ correctly' do
      # For $10.00 = 1000 cents: 3% = 30 cents + 30 cents = 60 cents
      expect(described_class.send(:calculate_stripe_fee_cents, 1000)).to eq(60)
    end
  end

  describe '.calculate_platform_fee_cents' do
    it 'uses 3% for premium tier' do
      premium_business = create(:business, tier: 'premium')
      # For $10.00 = 1000 cents: 3% = 30 cents
      expect(described_class.send(:calculate_platform_fee_cents, 1000, premium_business)).to eq(30)
    end

    it 'uses 5% for free tier' do
      free_business = create(:business, tier: 'free')
      # For $10.00 = 1000 cents: 5% = 50 cents
      expect(described_class.send(:calculate_platform_fee_cents, 1000, free_business)).to eq(50)
    end
  end

  describe '.get_stripe_price_id' do
    it 'returns correct ENV value for standard' do
      allow(ENV).to receive(:[]).with('STRIPE_STANDARD_PRICE_ID').and_return('price_standard_123')
      expect(described_class.get_stripe_price_id('standard')).to eq('price_standard_123')
    end

    it 'returns correct ENV value for premium' do
      allow(ENV).to receive(:[]).with('STRIPE_PREMIUM_PRICE_ID').and_return('price_premium_123')
      expect(described_class.get_stripe_price_id('premium')).to eq('price_premium_123')
    end
  end

  describe '.create_payment_checkout_session' do
    let(:mock_session) do
      double('Stripe::Checkout::Session', 
        id: 'cs_test123',
        url: 'https://checkout.stripe.com/pay/cs_test123',
        payment_intent: 'pi_test123'
      )
    end
    let(:mock_customer) { double('Stripe::Customer', id: 'cus_test123') }

    before do
      allow(StripeService).to receive(:ensure_stripe_customer_for_tenant).and_return(mock_customer)
      allow(Stripe::Checkout::Session).to receive(:create).and_return(mock_session)
    end

    it 'creates a checkout session with correct parameters' do
      success_url = 'http://example.com/success'
      cancel_url = 'http://example.com/cancel'

      result = StripeService.create_payment_checkout_session(
        invoice: invoice,
        success_url: success_url,
        cancel_url: cancel_url
      )

      expect(Stripe::Checkout::Session).to have_received(:create).with(
        hash_including(
          payment_method_types: ['card'],
          mode: 'payment',
          success_url: success_url,
          cancel_url: cancel_url,
          customer: 'cus_test123'
        )
      )

      expect(result[:session]).to eq(mock_session)
      expect(result[:payment]).to be_nil
    end

    it 'raises error for amounts below minimum' do
      low_amount_invoice = create(:invoice, business: business, tenant_customer: tenant_customer, total_amount: 0.25)

      expect {
        StripeService.create_payment_checkout_session(
          invoice: low_amount_invoice,
          success_url: 'http://example.com/success',
          cancel_url: 'http://example.com/cancel'
        )
      }.to raise_error(ArgumentError, /Payment amount must be at least/)
    end
  end

  describe '.handle_checkout_session_completed' do
    let(:session_data) do
      {
        'id' => 'cs_test123',
        'payment_intent' => 'pi_test123',
        'customer' => 'cus_test123',
        'metadata' => {
          'business_id' => business.id.to_s,
          'invoice_id' => invoice.id.to_s,
          'tenant_customer_id' => tenant_customer.id.to_s
        }
      }
    end

    it 'creates a payment record when checkout session is completed' do
      expect {
        StripeService.handle_checkout_session_completed(session_data)
      }.to change(Payment, :count).by(1)

      payment = Payment.last
      expect(payment.stripe_payment_intent_id).to eq('pi_test123')
      expect(payment.stripe_customer_id).to eq('cus_test123')
      expect(payment.status).to eq('completed')
      expect(payment.payment_method).to eq('credit_card')
      expect(payment.invoice).to eq(invoice)
      expect(payment.business).to eq(business)
      expect(payment.tenant_customer).to eq(tenant_customer)
    end

    it 'marks the invoice as paid' do
      invoice.update!(status: :pending)
      
      StripeService.handle_checkout_session_completed(session_data)
      
      expect(invoice.reload.status).to eq('paid')
    end

    it 'updates order status if order exists' do
      order = create(:order, business: business, tenant_customer: tenant_customer, status: :pending_payment)
      invoice.update!(order: order)
      
      StripeService.handle_checkout_session_completed(session_data)
      
      expect(order.reload.status).to eq('paid')
    end

    it 'does not create duplicate payment records' do
      # Create payment record first
      existing_payment = create(:payment, 
        stripe_payment_intent_id: 'pi_test123',
        business: business,
        invoice: invoice,
        tenant_customer: tenant_customer,
        status: :pending
      )

      expect {
        StripeService.handle_checkout_session_completed(session_data)
      }.not_to change(Payment, :count)

      expect(existing_payment.reload.status).to eq('completed')
    end
  end
end 