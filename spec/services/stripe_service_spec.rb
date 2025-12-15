require 'rails_helper'

RSpec.describe StripeService, type: :service do
  let(:business) { create(:business, stripe_account_id: 'acct_test123') }
  let(:tenant_customer) { create(:tenant_customer, business: business, stripe_customer_id: 'cus_test123') }
  let(:invoice) { create(:invoice, business: business, tenant_customer: tenant_customer, total_amount: 10.00) }

  before do
    allow(StripeService).to receive(:configure_stripe_api_key)
  end

  describe '.calculate_stripe_fee_cents' do
    it 'calculates 2.9% plus 30¢ correctly' do
      # For $10.00 = 1000 cents: 2.9% = 29 cents + 30 cents = 59 cents
      expect(described_class.send(:calculate_stripe_fee_cents, 1000)).to eq(59)
    end
  end

  describe '.calculate_platform_fee_cents' do
    it 'uses 1% platform fee for all businesses' do
      # For $10.00 = 1000 cents: 1% = 10 cents
      expect(described_class.send(:calculate_platform_fee_cents, 1000, business)).to eq(10)
    end

    it 'uses 1% even without a business argument' do
      # For $10.00 = 1000 cents: 1% = 10 cents
      expect(described_class.send(:calculate_platform_fee_cents, 1000)).to eq(10)
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
          customer: 'cus_test123',
          payment_intent_data: hash_including(application_fee_amount: 10)
        ),
        { stripe_account: business.stripe_account_id }
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
          ),
          payment_intent_data: hash_including(application_fee_amount: 10)
        ),
        { stripe_account: business.stripe_account_id }
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

  describe '.handle_client_document_payment_completion' do
    let(:business) { create(:business) }
    let(:customer) { create(:tenant_customer, business: business) }
    let(:service) do
      create(:service, business: business, service_type: :experience, price: 120, duration: 60, min_bookings: 1, max_bookings: 10, spots: 10)
    end
    let(:staff_member) { create(:staff_member, business: business) }
    let(:document) do
      create(
        :client_document,
        business: business,
        tenant_customer: customer,
        document_type: 'experience_booking',
        status: 'pending_payment',
        metadata: {
          'booking_payload' => {
            'service_id' => service.id,
            'staff_member_id' => staff_member.id,
            'start_time' => 1.day.from_now.iso8601,
            'end_time' => (1.day.from_now + 1.hour).iso8601,
            'notes' => 'Webhook booking',
            'tenant_customer_id' => customer.id,
            'booking_product_add_ons' => []
          }
        }
      )
    end
    let(:session_data) do
      {
        'id' => 'cs_doc_123',
        'payment_intent' => 'pi_doc_123',
        'customer' => 'cus_doc_123',
        'amount_total' => 5000,
        'metadata' => {
          'payment_type' => 'client_document',
          'client_document_id' => document.id,
          'business_id' => business.id
        }
      }
    end

    it 're-raises processor failures so webhook can retry' do
      allow(ClientDocuments::ExperienceBookingProcessor).to receive(:process!).and_raise(StandardError.new('boom'))

      expect {
        described_class.handle_client_document_payment_completion(session_data)
      }.to raise_error(StandardError, 'boom')
    end
  end

  describe ".handle_payment_completion with tips" do
    let(:business) { create(:business, stripe_account_id: "acct_test123") }
    let(:customer) { create(:tenant_customer, business: business) }
    let(:service) { create(:service, business: business, service_type: :experience, min_bookings: 1, max_bookings: 10, spots: 5) }
    let(:staff_member) { create(:staff_member, business: business) }
    let(:booking) { create(:booking, business: business, service: service, staff_member: staff_member, tenant_customer: customer) }
    let(:order) { create(:order, business: business, tenant_customer: customer, booking: booking) }
    let(:invoice) { create(:invoice, business: business, order: order, tenant_customer: customer, tip_amount: 10.0) }
    
    let(:session) do
      double(
        id: "cs_test_session123",
        client_reference_id: invoice.id.to_s,
        payment_intent: "pi_test123",
        metadata: { "tip_amount" => "10.0" }
      )
    end
    
    let(:payment_intent) do
      double(
        amount_received: 5000, # $50.00 in cents
        charges: double(data: [double(balance_transaction: double(fee: 145))]) # $1.45 fee
      )
    end

    before do
      allow(Stripe::PaymentIntent).to receive(:retrieve).and_return(payment_intent)
      allow(StripeService).to receive(:calculate_platform_fee).and_return(1.0)
    end

    context "with order tip" do
      it "creates payment with tip amount" do
        result = StripeService.handle_payment_completion(session)
        
        puts "Result: #{result.inspect}" if result[:success] == false
        expect(result[:success]).to be true
        payment = result[:payment]
        expect(payment.tip_amount).to eq(10.0)
        expect(payment.amount).to eq(50.0)
      end

      it "updates order with tip amount" do
        StripeService.handle_payment_completion(session)
        
        expect(order.reload.tip_amount).to eq(10.0)
        expect(order.status).to eq("paid")
      end

      it "creates tip record" do
        expect {
          StripeService.handle_payment_completion(session)
        }.to change(Tip, :count).by(1)
        
        tip = Tip.last
        expect(tip.amount).to eq(10.0)
        expect(tip.status).to eq("completed")
      end

      it "sends confirmation email with tip" do
        expect(InvoiceMailer).to receive(:payment_confirmation).with(invoice, anything).and_return(double(deliver_later: true))
        
        StripeService.handle_payment_completion(session)
      end
    end

    context 'with booking tip' do
      let(:service) { create(:service, business: business, service_type: :experience, min_bookings: 1, max_bookings: 10, spots: 5) }
      let(:staff_member) { create(:staff_member, business: business) }
      let(:booking) { create(:booking, business: business, service: service, staff_member: staff_member, tenant_customer: customer) }
      let(:invoice) { create(:invoice, business: business, booking: booking, tenant_customer: customer) }
      let(:session) do
        double('Stripe::Checkout::Session',
          id: 'cs_test_booking_tip_123',
          client_reference_id: invoice.id.to_s,
          payment_intent: 'pi_test_booking_tip_456',
          metadata: { 'tip_amount' => '15.0' }
        )
      end

      it 'creates booking tip record' do
        expect {
          StripeService.handle_payment_completion(session)
        }.to change(Tip, :count).by(1)

        tip = Tip.last
        expect(tip.booking).to eq(booking)
        expect(tip.amount).to eq(15.0)
        expect(tip.status).to eq('completed')
      end
    end

    context 'without tip' do
      let(:invoice) { create(:invoice, business: business, order: order, tenant_customer: customer, tip_amount: 0.0) }
      let(:session) do
        double('Stripe::Checkout::Session',
          id: 'cs_test_no_tip_123',
          client_reference_id: invoice.id.to_s,
          payment_intent: 'pi_test_no_tip_456',
          metadata: {}
        )
      end

      it 'does not create tip record' do
        expect {
          StripeService.handle_payment_completion(session)
        }.not_to change(Tip, :count)
      end

      it 'sends regular confirmation email' do
        expect(InvoiceMailer).to receive(:payment_confirmation).with(invoice, anything).and_return(double(deliver_later: true))
        
        StripeService.handle_payment_completion(session)
      end
    end
  end

  describe ".create_tip_payment_session" do
    let(:business) { create(:business, stripe_account_id: "acct_test123") }
    let(:booking) { create(:booking, business: business) }
    let(:tip) { create(:tip, business: business, booking: booking, amount: 25.0) }
    
    let(:stripe_session) do
      double(
        id: "cs_test_tip_session",
        url: "https://checkout.stripe.com/pay/test"
      )
    end

    before do
      allow(Stripe::Checkout::Session).to receive(:create).and_return(stripe_session)
    end

    it "creates Stripe checkout session for tip" do
      result = StripeService.create_tip_payment_session(
        tip: tip,
        success_url: "http://example.com/success",
        cancel_url: "http://example.com/cancel"
      )

      expect(result[:success]).to be true
      expect(result[:session]).to eq(stripe_session)
    end

    it "returns success with session" do
      result = StripeService.create_tip_payment_session(
        tip: tip,
        success_url: "http://example.com/success",
        cancel_url: "http://example.com/cancel"
      )

      expect(result[:success]).to be true
      expect(result[:session]).to eq(stripe_session)
    end

    it "creates session with correct parameters" do
      StripeService.create_tip_payment_session(
        tip: tip,
        success_url: "http://example.com/success",
        cancel_url: "http://example.com/cancel"
      )

      expect(Stripe::Checkout::Session).to have_received(:create).with(
        hash_including(
          line_items: array_including(
            hash_including(
              price_data: hash_including(
                unit_amount: 2500, # $25.00 in cents
                product_data: hash_including(
                  name: "Tip for #{business.name}"
                )
              )
            )
          ),
          client_reference_id: tip.id.to_s,
          metadata: hash_including(
            tip_id: tip.id.to_s,
            business_id: business.id.to_s
          ),
          payment_intent_data: hash_including(application_fee_amount: 25)
        ),
        { stripe_account: business.stripe_account_id }
      )
    end

    context "with invalid tip amount" do
      let(:tip) { create(:tip, business: business, booking: booking, amount: 0.25) }

      it "raises error for amount below minimum" do
        expect {
          StripeService.create_tip_payment_session(
            tip: tip,
            success_url: "http://example.com/success",
            cancel_url: "http://example.com/cancel"
          )
        }.to raise_error(ArgumentError, "Tip amount must be at least $0.50")
      end
    end

    context "without Stripe Connect account" do
      let(:business) { create(:business, stripe_account_id: nil) }

      it "raises error" do
        expect {
          StripeService.create_tip_payment_session(
            tip: tip,
            success_url: "http://example.com/success",
            cancel_url: "http://example.com/cancel"
          )
        }.to raise_error(ArgumentError, "Business must have a connected Stripe account to process tips")
      end
    end
  end

  describe "tip fee calculations" do
    describe ".calculate_tip_stripe_fee" do
      it "calculates 2.9% + $0.30 Stripe fee" do
        fee = StripeService.calculate_tip_stripe_fee(100.0)
        expect(fee).to eq(3.20) # (100.0 * 0.029) + 0.30 = 2.90 + 0.30 = 3.20
      end

      it "rounds to 2 decimal places" do
        fee = StripeService.calculate_tip_stripe_fee(33.33)
        expect(fee).to eq(1.27) # (33.33 * 0.029) + 0.30 = 0.97 + 0.30 = 1.27
      end
    end

    describe ".calculate_tip_platform_fee" do
      it "calculates 1% platform fee for tips" do
        fee = StripeService.calculate_tip_platform_fee(100.0, business)
        expect(fee).to eq(1.0) # 1% of $100.00 = $1.00
      end

      it "calculates 1% for any business" do
        another_business = create(:business)
        fee = StripeService.calculate_tip_platform_fee(100.0, another_business)
        expect(fee).to eq(1.0) # 1% of $100.00 = $1.00
      end
    end

    describe ".calculate_tip_business_amount" do
      it "calculates business amount after fees (direct charges)" do
        # In direct charges, business pays Stripe fees directly, so we deduct both Stripe and platform fees
        amount = StripeService.calculate_tip_business_amount(100.0, business)
        expect(amount).to eq(95.8) # 100 - 3.20 (Stripe fee with flat fee) - 1.00 (1% platform fee)
      end
    end
  end
end 