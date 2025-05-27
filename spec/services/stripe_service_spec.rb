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

  describe '.create_payment_checkout_session_for_booking' do
    let(:mock_session) do
      double('Stripe::Checkout::Session', 
        id: 'cs_booking_test123',
        url: 'https://checkout.stripe.com/pay/cs_booking_test123',
        payment_intent: 'pi_booking_test123'
      )
    end
    let(:mock_customer) { double('Stripe::Customer', id: 'cus_test123') }
    let(:booking_data) do
      {
        service_id: 1,
        staff_member_id: 1,
        start_time: 1.day.from_now.iso8601,
        end_time: (1.day.from_now + 1.hour).iso8601,
        notes: 'Test booking',
        tenant_customer_id: tenant_customer.id,
        booking_product_add_ons: []
      }
    end

    before do
      allow(StripeService).to receive(:ensure_stripe_customer_for_tenant).and_return(mock_customer)
      allow(Stripe::Checkout::Session).to receive(:create).and_return(mock_session)
    end

    it 'creates a checkout session with booking data in metadata' do
      success_url = 'http://example.com/success'
      cancel_url = 'http://example.com/cancel'

      result = StripeService.create_payment_checkout_session_for_booking(
        invoice: invoice,
        booking_data: booking_data,
        success_url: success_url,
        cancel_url: cancel_url
      )

      expect(Stripe::Checkout::Session).to have_received(:create).with(
        hash_including(
          payment_method_types: ['card'],
          mode: 'payment',
          success_url: success_url,
          cancel_url: cancel_url,
          customer: 'cus_test123',
          metadata: hash_including(
            booking_type: 'service_booking',
            booking_data: booking_data.to_json
          )
        )
      )

      expect(result[:session]).to eq(mock_session)
      expect(result[:payment]).to be_nil
    end

    it 'raises error for amounts below minimum' do
      low_amount_invoice = create(:invoice, business: business, tenant_customer: tenant_customer, total_amount: 0.25)

      expect {
        StripeService.create_payment_checkout_session_for_booking(
          invoice: low_amount_invoice,
          booking_data: booking_data,
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

  describe '.handle_booking_payment_completion' do
    let!(:service) { create(:service, business: business, price: 50.00) }
    let!(:staff_member) { create(:staff_member, business: business) }
    let!(:default_tax_rate) { create(:tax_rate, business: business, name: 'Default Tax', rate: 0.098) }
    let(:booking_session_data) do
      {
        'id' => 'cs_booking_test123',
        'payment_intent' => 'pi_booking_test123',
        'customer' => 'cus_test123',
        'metadata' => {
          'business_id' => business.id.to_s,
          'tenant_customer_id' => tenant_customer.id.to_s,
          'booking_type' => 'service_booking',
          'booking_data' => {
            service_id: service.id,
            staff_member_id: staff_member.id,
            start_time: 1.day.from_now.iso8601,
            end_time: (1.day.from_now + 1.hour).iso8601,
            notes: 'Test booking from webhook',
            tenant_customer_id: tenant_customer.id,
            booking_product_add_ons: []
          }.to_json
        }
      }
    end

    it 'creates booking and payment after successful payment' do
      expect {
        StripeService.handle_booking_payment_completion(booking_session_data)
      }.to change(Booking, :count).by(1)
       .and change(Payment, :count).by(1)
       .and change(Invoice, :count).by(1)

      booking = Booking.last
      expect(booking.service).to eq(service)
      expect(booking.staff_member).to eq(staff_member)
      expect(booking.tenant_customer).to eq(tenant_customer)
      expect(booking.status).to eq('confirmed')
      expect(booking.notes).to eq('Test booking from webhook')

      payment = Payment.last
      expect(payment.stripe_payment_intent_id).to eq('pi_booking_test123')
      expect(payment.stripe_customer_id).to eq('cus_test123')
      expect(payment.status).to eq('completed')
      expect(payment.payment_method).to eq('credit_card')
      expect(payment.invoice.booking).to eq(booking)

      invoice = Invoice.last
      expect(invoice.status).to eq('paid')
      expect(invoice.booking).to eq(booking)
      expect(invoice.tax_rate).to eq(default_tax_rate)
      expect(invoice.tax_amount).to be_within(0.01).of(4.90) # 9.8% of $50
      expect(invoice.total_amount).to be_within(0.01).of(54.90) # $50 + $4.90 tax
    end

    it 'handles missing business or customer gracefully' do
      invalid_session_data = booking_session_data.dup
      invalid_session_data['metadata']['business_id'] = '999999'

      allow(Rails.logger).to receive(:error)

      expect {
        StripeService.handle_booking_payment_completion(invalid_session_data)
      }.not_to change(Booking, :count)

      expect(Rails.logger).to have_received(:error).with(/Could not find business/)
    end
  end
end 