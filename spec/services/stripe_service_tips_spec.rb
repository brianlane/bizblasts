require 'rails_helper'

RSpec.describe StripeService, type: :service do
  let(:business) { create(:business, tips_enabled: true, stripe_account_id: 'acct_test123', tier: 'premium') }
  let(:tenant_customer) { create(:tenant_customer, business: business, stripe_customer_id: 'cus_test123') }
  let(:experience_service) { create(:service, business: business, service_type: :experience, duration: 60, min_bookings: 1, max_bookings: 10, spots: 5) }
  let(:booking) { create(:booking, business: business, service: experience_service, tenant_customer: tenant_customer, start_time: 2.hours.ago) }
  let(:tip) { create(:tip, business: business, booking: booking, tenant_customer: tenant_customer, amount: 10.00) }

  before do
    allow(StripeService).to receive(:configure_stripe_api_key)
    ActsAsTenant.current_tenant = business
  end

  describe '.create_tip_checkout_session' do
    let(:mock_session) do
      double('Stripe::Checkout::Session', 
        id: 'cs_tip_test123',
        url: 'https://checkout.stripe.com/pay/cs_tip_test123',
        payment_intent: 'pi_tip_test123'
      )
    end
    let(:mock_customer) { double('Stripe::Customer', id: 'cus_test123') }

    before do
      allow(StripeService).to receive(:ensure_stripe_customer_for_tenant).and_return(mock_customer)
      allow(Stripe::Checkout::Session).to receive(:create).and_return(mock_session)
    end

    it 'creates a checkout session with correct parameters' do
      success_url = 'http://example.com/tip/success'
      cancel_url = 'http://example.com/tip/cancel'

      result = StripeService.create_tip_checkout_session(
        tip: tip,
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
          line_items: [
            hash_including(
              price_data: hash_including(
                currency: 'usd',
                unit_amount: 1000, # $10.00 in cents
                product_data: hash_including(
                  name: "Tip for #{business.name}",
                  description: "Thank you for your experience with #{business.name}"
                )
              ),
              quantity: 1
            )
          ],
          payment_intent_data: hash_including(
            application_fee_amount: 30, # Platform fees now applied for tips (3% of $10.00 = $0.30 for premium tier)
            transfer_data: { destination: business.stripe_account_id },
            metadata: hash_including(
              business_id: business.id,
              tip_id: tip.id,
              tenant_customer_id: tenant_customer.id,
              payment_type: 'tip'
            )
          ),
          metadata: hash_including(
            business_id: business.id,
            tip_id: tip.id,
            tenant_customer_id: tenant_customer.id,
            payment_type: 'tip'
          )
        )
      )

      expect(result[:session]).to eq(mock_session)
      expect(result[:tip]).to eq(tip)
    end

    it 'raises error for amounts below minimum' do
      low_booking = create(:booking, business: business, tenant_customer: tenant_customer)
      low_amount_tip = build(:tip, business: business, booking: low_booking, tenant_customer: tenant_customer, amount: 0.25)
      # Skip validation to create the tip with invalid business_amount
      low_amount_tip.save(validate: false)

      expect {
        StripeService.create_tip_checkout_session(
          tip: low_amount_tip,
          success_url: 'http://example.com/success',
          cancel_url: 'http://example.com/cancel'
        )
      }.to raise_error(ArgumentError, /Tip amount must be at least/)
    end

    it 'ensures Stripe customer for tenant' do
      StripeService.create_tip_checkout_session(
        tip: tip,
        success_url: 'http://example.com/success',
        cancel_url: 'http://example.com/cancel'
      )

      expect(StripeService).to have_received(:ensure_stripe_customer_for_tenant).with(tenant_customer)
    end
  end

  describe '.handle_tip_payment_completion' do
    include ActiveSupport::Testing::TimeHelpers
    
    let(:session_data) do
      {
        'id' => 'cs_tip_test123',
        'payment_intent' => 'pi_tip_test123',
        'customer' => 'cus_test123',
        'metadata' => {
          'business_id' => business.id.to_s,
          'tip_id' => tip.id.to_s,
          'tenant_customer_id' => tenant_customer.id.to_s,
          'payment_type' => 'tip'
        }
      }
    end

    it 'updates tip record with payment completion and fee tracking' do
      travel_to Time.current do
        StripeService.handle_tip_payment_completion(session_data)
        
        tip.reload
        expect(tip.stripe_payment_intent_id).to eq('pi_tip_test123')
        expect(tip.stripe_customer_id).to eq('cus_test123')
        expect(tip.status).to eq('completed')
        expect(tip.paid_at).to be_within(1.second).of(Time.current)
        
        # Check fee calculations for $10.00 tip on premium tier business (3% platform fee)
        expect(tip.stripe_fee_amount).to eq(0.59) # 2.9% + $0.30 = $0.29 + $0.30 = $0.59
        expect(tip.platform_fee_amount).to eq(0.30) # 3% of $10.00 = $0.30
        expect(tip.business_amount).to eq(9.11) # $10.00 - $0.59 - $0.30 = $9.11
      end
    end
    
    it 'calculates different platform fees for free tier business' do
      # Test the platform fee calculation method directly to ensure it works correctly
      free_business = create(:business, tier: 'free')
      standard_business = create(:business, tier: 'standard')
      
      # Test platform fee calculation for different tiers
      amount_cents = 1000 # $10.00
      
      free_platform_fee = StripeService.send(:calculate_platform_fee_cents, amount_cents, free_business)
      expect(free_platform_fee).to eq(50) # 5% of $10.00 = 50 cents
      
      standard_platform_fee = StripeService.send(:calculate_platform_fee_cents, amount_cents, standard_business)
      expect(standard_platform_fee).to eq(50) # 5% of $10.00 = 50 cents (standard is also 5%)
      
      premium_platform_fee = StripeService.send(:calculate_platform_fee_cents, amount_cents, business) # business is premium
      expect(premium_platform_fee).to eq(30) # 3% of $10.00 = 30 cents
    end

    it 'handles missing business gracefully' do
      invalid_session_data = session_data.dup
      invalid_session_data['metadata']['business_id'] = '999999'

      allow(Rails.logger).to receive(:error)

      expect {
        StripeService.handle_tip_payment_completion(invalid_session_data)
      }.not_to change { tip.reload.status }

      expect(Rails.logger).to have_received(:error).with(/Could not find business/)
    end

    it 'handles missing tip gracefully' do
      invalid_session_data = session_data.dup
      invalid_session_data['metadata']['tip_id'] = '999999'

      allow(Rails.logger).to receive(:error)

      expect {
        StripeService.handle_tip_payment_completion(invalid_session_data)
      }.not_to change { tip.reload.status }

      expect(Rails.logger).to have_received(:error).with(/Could not find tip/)
    end

    it 'handles missing tenant customer gracefully' do
      invalid_session_data = session_data.dup
      invalid_session_data['metadata']['tenant_customer_id'] = '999999'

      allow(Rails.logger).to receive(:error)

      expect {
        StripeService.handle_tip_payment_completion(invalid_session_data)
      }.not_to change { tip.reload.status }

      expect(Rails.logger).to have_received(:error).with(/Could not find tip/)
    end

    it 'handles missing metadata gracefully' do
      invalid_session_data = {
        'id' => 'cs_tip_test123',
        'payment_intent' => 'pi_tip_test123',
        'customer' => 'cus_test123',
        'metadata' => {}
      }

      allow(Rails.logger).to receive(:error)

      expect {
        StripeService.handle_tip_payment_completion(invalid_session_data)
      }.not_to change { tip.reload.status }

      expect(Rails.logger).to have_received(:error).with(/Missing required metadata/)
    end

    it 'logs successful completion' do
      allow(Rails.logger).to receive(:info)

      StripeService.handle_tip_payment_completion(session_data)

      expect(Rails.logger).to have_received(:info).with(/Successfully processed tip payment #{tip.id}/)
    end

    it 'handles exceptions gracefully' do
      # Mock the business.tips.find_by to raise an error within the ActsAsTenant block
      allow_any_instance_of(Business).to receive(:tips).and_raise(StandardError.new('Database error'))
      allow(Rails.logger).to receive(:error)

      expect {
        StripeService.handle_tip_payment_completion(session_data)
      }.not_to raise_error

      expect(Rails.logger).to have_received(:error).with(/\[TIP\] Error processing tip payment for session/)
    end
  end

  describe '.handle_checkout_session_completed with tip payment' do
    let(:tip_session_data) do
      {
        'id' => 'cs_tip_test123',
        'payment_intent' => 'pi_tip_test123',
        'customer' => 'cus_test123',
        'metadata' => {
          'business_id' => business.id.to_s,
          'tip_id' => tip.id.to_s,
          'tenant_customer_id' => tenant_customer.id.to_s,
          'payment_type' => 'tip'
        }
      }
    end

    it 'routes tip payments to tip handler' do
      allow(StripeService).to receive(:handle_tip_payment_completion)

      StripeService.handle_checkout_session_completed(tip_session_data)

      expect(StripeService).to have_received(:handle_tip_payment_completion).with(tip_session_data)
    end

    it 'returns early after handling tip payment' do
      allow(StripeService).to receive(:handle_tip_payment_completion)
      allow(StripeService).to receive(:handle_booking_payment_completion)

      StripeService.handle_checkout_session_completed(tip_session_data)

      expect(StripeService).to have_received(:handle_tip_payment_completion)
      expect(StripeService).not_to have_received(:handle_booking_payment_completion)
    end
  end
end 