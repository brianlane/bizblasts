require 'rails_helper'

RSpec.describe ReferralService, type: :service do
  let!(:business) { create(:business) }
  let!(:service) { create(:service, business: business, price: 100.00) }
  let!(:product) { create(:product, business: business, price: 50.00) }
  let!(:product_variant) { create(:product_variant, product: product, price_modifier: 0.00) }
  let!(:staff_member) { create(:staff_member, business: business) }
  
  # Setup referral program
  let!(:referral_program) do
    business.create_referral_program!(
      active: true,
      referrer_reward_type: 'points',
      referrer_reward_value: 100,
      referral_code_discount_amount: 10.0,
      min_purchase_amount: 0.0
    )
  end

  before do
    business.update!(
      referral_program_enabled: true,
      loyalty_program_enabled: true,
      points_per_dollar: 1.0
    )
    ActsAsTenant.current_tenant = business
  end

  # Clear association caches before each test to prevent test pollution
  before do
    business.association(:referral_program).reset if business.association(:referral_program).loaded?
  end

  describe '#generate_referral_code' do
    let!(:client_user) { create(:user, :client) }

    context 'when business has referral program enabled' do
      it 'generates a unique referral code for a client user' do
        code = ReferralService.generate_referral_code(client_user, business)
        
        expect(code).to be_present
        expect(code).to match(/^REF-[A-Z0-9]{8}$/)
        
        # Verify referral record was created
        referral = Referral.find_by(referrer: client_user, business: business)
        expect(referral).to be_present
        expect(referral.referral_code).to eq(code)
        expect(referral.status).to eq('pending')
      end

      it 'returns existing code for same user-business combination' do
        first_code = ReferralService.generate_referral_code(client_user, business)
        second_code = ReferralService.generate_referral_code(client_user, business)
        
        expect(first_code).to eq(second_code)
        expect(Referral.where(referrer: client_user, business: business).count).to eq(1)
      end
    end

    context 'when business has referral program disabled' do
      before { business.update!(referral_program_enabled: false) }

      it 'returns nil' do
        code = ReferralService.generate_referral_code(client_user, business)
        expect(code).to be_nil
      end
    end

    context 'when user is not a client' do
      let!(:manager_user) { create(:user, :manager, business: business) }

      it 'returns nil' do
        code = ReferralService.generate_referral_code(manager_user, business)
        expect(code).to be_nil
      end
    end
  end

  describe '#validate_referral_code' do
    let!(:referrer_user) { create(:user, :client) }
    let!(:referral) { create(:referral, business: business, referrer: referrer_user) }
    let!(:customer) { create(:tenant_customer, business: business) }

    context 'with valid referral code' do
      it 'returns valid result' do
        result = ReferralService.validate_referral_code(referral.referral_code, business, customer)
        
        expect(result[:valid]).to be true
        expect(result[:referral]).to eq(referral)
      end
    end

    context 'with invalid referral code' do
      it 'returns invalid result for non-existent code' do
        result = ReferralService.validate_referral_code('INVALID-CODE', business, customer)
        
        expect(result[:valid]).to be false
        expect(result[:error]).to eq('Invalid referral code')
      end

      it 'returns invalid result for empty code' do
        result = ReferralService.validate_referral_code('', business, customer)
        
        expect(result[:valid]).to be false
        expect(result[:error]).to eq('Code required')
      end
    end

    context 'when referral program is inactive' do
      before do
        referral_program.update!(active: false)
        # Clear association cache after update
        business.association(:referral_program).reset
      end
      
      after do
        # Reset back to original state to avoid state pollution
        referral_program.reload.update!(active: true)
        # Clear association cache after reset
        business.association(:referral_program).reset
      end

      it 'returns invalid result' do
        result = ReferralService.validate_referral_code(referral.referral_code, business, customer)
        
        expect(result[:valid]).to be false
        expect(result[:error]).to eq('Referral program not active')
      end
    end

    context 'when referral is already used' do
      before { referral.update!(status: 'qualified') }

      it 'returns invalid result' do
        result = ReferralService.validate_referral_code(referral.referral_code, business, customer)
        
        expect(result[:valid]).to be false
        expect(result[:error]).to eq('This referral code has already been used')
      end
    end
  end

  describe '#process_referral_checkout' do
    let!(:referrer_user) { create(:user, :client) }
    let!(:referral) { create(:referral, business: business, referrer: referrer_user) }
    
    context 'with booking transaction' do
      let!(:customer) { create(:tenant_customer, business: business) }
      let!(:booking) do
        create(:booking, 
          business: business, 
          tenant_customer: customer, 
          service: service, 
          staff_member: staff_member,
          amount: 100.00
        )
      end

      it 'successfully processes the referral' do
        result = ReferralService.process_referral_checkout(referral, booking, customer)
        
        expect(result[:success]).to be true
        expect(result[:referral]).to eq(referral)
        
        # Verify referral was marked as qualified
        referral.reload
        expect(referral.status).to eq('rewarded')
        expect(referral.referred_tenant_customer).to eq(customer)
        expect(referral.qualifying_booking).to eq(booking)
        expect(referral.qualification_met_at).to be_present
        expect(referral.reward_issued_at).to be_present
        
        # Verify referrer received loyalty points
        referrer_customer = TenantCustomer.find_by(business: business, email: referrer_user.email)
        expect(referrer_customer).to be_present
        expect(referrer_customer.current_loyalty_points).to eq(100)
      end
    end

    context 'with order transaction' do
      let!(:customer) { create(:tenant_customer, business: business) }
      let!(:order) do
        create(:order, 
          business: business, 
          tenant_customer: customer, 
          total_amount: 50.00
        )
      end

      it 'successfully processes the referral' do
        result = ReferralService.process_referral_checkout(referral, order, customer)
        
        expect(result[:success]).to be true
        
        # Verify referral was marked as qualified
        referral.reload
        expect(referral.status).to eq('rewarded')
        expect(referral.referred_tenant_customer).to eq(customer)
        expect(referral.qualifying_order).to eq(order)
      end
    end

    context 'when minimum purchase amount is not met' do
      let!(:customer) { create(:tenant_customer, business: business) }
      let(:small_order) do
        create(:order, 
          business: business, 
          tenant_customer: customer, 
          total_amount: 5.00
        )
      end

      before do 
        # Set the minimum purchase amount for this test
        referral_program.update!(min_purchase_amount: 25.00)
        # CRITICAL: Clear the association cache so business.referral_program picks up the change
        business.association(:referral_program).reset

        # Stub out calculate_totals! to prevent recalculation of total_amount
        allow_any_instance_of(Order).to receive(:calculate_totals!).and_return(nil)
      end
      
      after do
        # Reset back to original state to avoid state pollution
        referral_program.reload.update!(min_purchase_amount: 0.0)
        # Clear association cache after reset
        business.association(:referral_program).reset
      end

      it 'fails with minimum purchase error' do
        result = ReferralService.process_referral_checkout(referral, small_order, customer)
        
        expect(result[:success]).to be false
        expect(result[:error]).to include('Purchase minimum of 25.0 not met')
        
        # Verify referral was not processed
        referral.reload
        expect(referral.status).to eq('pending')
      end
    end

    context 'when referral is not pending' do
      let!(:customer) { create(:tenant_customer, business: business) }
      let!(:booking) { create(:booking, business: business, tenant_customer: customer, service: service) }

      before { referral.update!(status: 'qualified') }

      it 'fails with status error' do
        result = ReferralService.process_referral_checkout(referral, booking, customer)
        
        expect(result[:success]).to be false
        expect(result[:error]).to eq('Referral is not pending')
      end
    end

    context 'when referral program is inactive' do
      let!(:customer) { create(:tenant_customer, business: business) }
      let!(:booking) { create(:booking, business: business, tenant_customer: customer, service: service) }

      before do
        referral_program.update!(active: false)
        # Clear association cache after update
        business.association(:referral_program).reset
      end
      
      after do
        # Reset back to original state to avoid state pollution
        referral_program.reload.update!(active: true)
        # Clear association cache after reset
        business.association(:referral_program).reset
      end

      it 'fails with program inactive error' do
        result = ReferralService.process_referral_checkout(referral, booking, customer)
        
        expect(result[:success]).to be false
        expect(result[:error]).to eq('Referral program is not active')
      end
    end
  end

  describe 'Referral code usage scenarios' do
    let!(:referrer_user) { create(:user, :client, email: 'referrer@example.com') }
    let!(:referral) { create(:referral, business: business, referrer: referrer_user) }

    context 'Client user (referrer) uses their own referral code' do
      let!(:referrer_customer) { create(:tenant_customer, business: business, email: 'referrer@example.com') }
      let!(:booking) { create(:booking, business: business, tenant_customer: referrer_customer, service: service, amount: 100.00) }

      it 'allows self-referral and processes successfully' do
        # Apply referral code via PromoCodeService
        result = PromoCodeService.apply_code(referral.referral_code, business, booking, referrer_customer)
        
        expect(result[:success]).to be true
        expect(result[:type]).to eq('referral')
        expect(result[:discount_amount]).to eq(10.0)
        
        # Verify booking was updated
        booking.reload
        expect(booking.applied_promo_code).to eq(referral.referral_code)
        expect(booking.promo_discount_amount).to eq(10.0)
        expect(booking.promo_code_type).to eq('referral')
        
        # Verify referral was processed
        referral.reload
        expect(referral.status).to eq('rewarded')
        expect(referral.referred_tenant_customer).to eq(referrer_customer)
        
        # Verify referrer received loyalty points (self-referral reward)
        expect(referrer_customer.current_loyalty_points).to eq(100)
      end
    end

    context 'Different client user uses the referral code' do
      let!(:different_user) { create(:user, :client, email: 'different@example.com') }
      let!(:different_customer) { create(:tenant_customer, business: business, email: 'different@example.com') }
      let!(:order) { create(:order, business: business, tenant_customer: different_customer, total_amount: 75.00) }

      it 'processes referral successfully' do
        result = PromoCodeService.apply_code(referral.referral_code, business, order, different_customer)
        
        expect(result[:success]).to be true
        expect(result[:type]).to eq('referral')
        expect(result[:discount_amount]).to eq(10.0)
        
        # Verify order was updated
        order.reload
        expect(order.applied_promo_code).to eq(referral.referral_code)
        expect(order.promo_discount_amount).to eq(10.0)
        expect(order.promo_code_type).to eq('referral')
        
        # Verify referral was processed
        referral.reload
        expect(referral.status).to eq('rewarded')
        expect(referral.referred_tenant_customer).to eq(different_customer)
        
        # Verify both users have correct points
        referrer_customer = TenantCustomer.find_by(business: business, email: referrer_user.email)
        expect(referrer_customer.current_loyalty_points).to eq(100) # Referral reward
      end
    end

    context 'Guest user (tenant customer without account) uses the referral code' do
      let!(:guest_customer) { create(:tenant_customer, business: business, email: 'guest@example.com') }
      let!(:booking) { create(:booking, business: business, tenant_customer: guest_customer, service: service, amount: 100.00) }

      it 'processes referral successfully for guest checkout' do
        result = PromoCodeService.apply_code(referral.referral_code, business, booking, guest_customer)
        
        expect(result[:success]).to be true
        expect(result[:type]).to eq('referral')
        expect(result[:discount_amount]).to eq(10.0)
        
        # Verify booking was updated
        booking.reload
        expect(booking.applied_promo_code).to eq(referral.referral_code)
        expect(booking.promo_discount_amount).to eq(10.0)
        expect(booking.promo_code_type).to eq('referral')
        
        # Verify referral was processed
        referral.reload
        expect(referral.status).to eq('rewarded')
        expect(referral.referred_tenant_customer).to eq(guest_customer)
        
        # Verify referrer received loyalty points
        referrer_customer = TenantCustomer.find_by(business: business, email: referrer_user.email)
        expect(referrer_customer.current_loyalty_points).to eq(100)
      end
    end
  end

  describe 'Edge cases and error handling' do
    let!(:referrer_user) { create(:user, :client) }
    let!(:referral) { create(:referral, business: business, referrer: referrer_user) }
    let!(:customer) { create(:tenant_customer, business: business) }

    context 'when attempting to use an already qualified referral code' do
      let!(:booking) { create(:booking, business: business, tenant_customer: customer, service: service) }

      before { referral.update!(status: 'qualified') }

      it 'fails validation and cannot be applied' do
        # First, validate the code
        validation = ReferralService.validate_referral_code(referral.referral_code, business, customer)
        expect(validation[:valid]).to be false
        expect(validation[:error]).to eq('This referral code has already been used')
        
        # Try to apply anyway (should fail)
        result = PromoCodeService.apply_code(referral.referral_code, business, booking, customer)
        expect(result[:success]).to be false
      end
    end

    context 'when business has no referral program' do
      let!(:business_without_program) { create(:business, hostname: 'no-program', referral_program_enabled: false) }
      let!(:customer_no_program) { create(:tenant_customer, business: business_without_program) }

      it 'fails validation' do
        # Use a fake referral code since businesses without referral programs shouldn't have referrals
        fake_code = 'REF-FAKE123'
        result = ReferralService.validate_referral_code(fake_code, business_without_program, customer_no_program)
        
        expect(result[:valid]).to be false
        expect(result[:error]).to eq('Invalid referral code')
      end
    end

    context 'when referral code is applied via different endpoints' do
      let!(:booking) { create(:booking, business: business, tenant_customer: customer, service: service, amount: 100.00) }
      let!(:order) { create(:order, business: business, tenant_customer: customer, total_amount: 50.00) }

      it 'works correctly for both booking (/book) and order (/orders/new) endpoints' do
        # Test booking endpoint
        booking_result = PromoCodeService.apply_code(referral.referral_code, business, booking, customer)
        expect(booking_result[:success]).to be true
        expect(booking_result[:discount_amount]).to eq(10.0)
        
        # Create a new referral for order test (since the first one is now used)
        new_referral = create(:referral, business: business, referrer: referrer_user)
        
        # Test order endpoint
        order_result = PromoCodeService.apply_code(new_referral.referral_code, business, order, customer)
        expect(order_result[:success]).to be true
        expect(order_result[:discount_amount]).to eq(10.0)
      end
    end
  end
end 