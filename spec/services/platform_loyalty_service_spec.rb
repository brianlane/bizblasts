require 'rails_helper'

RSpec.describe PlatformLoyaltyService, type: :service do
  let(:referring_business) do
    business = create(:business, name: 'Test Business')
    business.update!(platform_referral_code: 'BIZ-TB-ABC123')
    business
  end
  let(:referred_business) { create(:business, name: 'New Business') }
  
  before do
    # Reset any existing Stripe mocks to prevent interference from other tests
    RSpec::Mocks.space.reset_all
    
    # Set up default Stripe coupon mock for all tests
    allow(Stripe::Coupon).to receive(:create).and_return(
      double('Stripe::Coupon', id: 'coupon_default_123')
    )
  end

  after do
    # Reset the current tenant to prevent test pollution
    ActsAsTenant.current_tenant = nil
    
    # Clear Rails cache to prevent interference
    Rails.cache.clear
    
    # Reset all mocks to ensure clean state for next test
    RSpec::Mocks.space.reset_all
  end

  describe '.process_business_referral_signup' do
    context 'with valid referral code' do
      it 'creates platform referral and awards points' do
        # Mock Stripe coupon creation
        mock_stripe_coupon = double('Stripe::Coupon', id: 'coupon_test_referral_123')
        allow(Stripe::Coupon).to receive(:create).and_return(mock_stripe_coupon)
        
        expect {
          result = PlatformLoyaltyService.process_business_referral_signup(
            referred_business, 
            referring_business.platform_referral_code
          )
          
          expect(result[:success]).to be true
          expect(result[:points_awarded]).to eq(500)
        }.to change(PlatformReferral, :count).by(1)
         .and change(PlatformLoyaltyTransaction, :count).by(1)
         .and change(PlatformDiscountCode, :count).by(1)
      end
      
      it 'creates Stripe coupon for referral discount' do
        # Clear any existing mocks and set up specific expectation for this test
        RSpec::Mocks.space.reset_all
        
        mock_stripe_coupon = double('Stripe::Coupon', id: 'coupon_test_referral_123')
        expect(Stripe::Coupon).to receive(:create).with(
          hash_including(
            percent_off: 50,
            duration: 'once',
            name: 'BizBlasts Business Referral - 50% Off First Month',
            metadata: { source: 'bizblasts_business_referral' }
          )
        ).and_return(mock_stripe_coupon)
        
        PlatformLoyaltyService.process_business_referral_signup(
          referred_business, 
          referring_business.platform_referral_code
        )
        
        discount_code = PlatformDiscountCode.last
        expect(discount_code.stripe_coupon_id).to eq('coupon_test_referral_123')
        expect(discount_code.discount_amount).to eq(50)
        expect(discount_code.points_redeemed).to eq(0) # Referral reward, not point redemption
      end
      
      it 'awards 500 points to referring business' do
        mock_stripe_coupon = double('Stripe::Coupon', id: 'coupon_test_referral_123')
        allow(Stripe::Coupon).to receive(:create).and_return(mock_stripe_coupon)
        
        expect {
          PlatformLoyaltyService.process_business_referral_signup(
            referred_business, 
            referring_business.platform_referral_code
          )
        }.to change { referring_business.reload.platform_loyalty_points }.by(500)
        
        transaction = referring_business.platform_loyalty_transactions.last
        expect(transaction.transaction_type).to eq('earned')
        expect(transaction.points_amount).to eq(500)
        expect(transaction.description).to include('Business referral reward')
      end
    end
    
    context 'with invalid referral code' do
      it 'returns error for non-existent code' do
        result = PlatformLoyaltyService.process_business_referral_signup(
          referred_business, 
          'INVALID-CODE'
        )
        
        expect(result[:success]).to be false
        expect(result[:error]).to eq('Invalid referral code')
      end
    end
    
    context 'with self-referral attempt' do
      it 'prevents business from referring itself' do
        result = PlatformLoyaltyService.process_business_referral_signup(
          referring_business, 
          referring_business.platform_referral_code
        )
        
        expect(result[:success]).to be false
        expect(result[:error]).to eq('Businesses cannot refer themselves')
      end
    end
    
    context 'with duplicate referral' do
      it 'prevents duplicate referrals' do
        # Create existing referral
        PlatformReferral.create!(
          referrer_business: referring_business,
          referred_business: referred_business,
          referral_code: referring_business.platform_referral_code,
          status: 'qualified'
        )
        
        result = PlatformLoyaltyService.process_business_referral_signup(
          referred_business, 
          referring_business.platform_referral_code
        )
        
        expect(result[:success]).to be false
        expect(result[:error]).to eq('Referral already exists')
      end
    end
  end
  
  describe '.redeem_loyalty_points' do
    let(:business_with_points) do
      business = create(:business)
      business.add_platform_loyalty_points!(500, 'Test setup points', nil)
      business
    end
    
    context 'with valid point redemption' do
      it 'creates discount code and deducts points' do
        # Mock Stripe coupon creation
        mock_stripe_coupon = double('Stripe::Coupon', id: 'coupon_test_loyalty_123')
        expect(Stripe::Coupon).to receive(:create).with(
          hash_including(
            amount_off: 2000, # $20 in cents
            currency: 'usd',
            duration: 'once',
            name: 'BizBlasts Loyalty Reward - $20 Off',
            metadata: {
              source: 'bizblasts_loyalty_redemption',
              discount_amount: 20
            }
          )
        ).and_return(mock_stripe_coupon)
        
        expect {
          result = PlatformLoyaltyService.redeem_loyalty_points(business_with_points, 200)
          
          expect(result[:success]).to be true
          expect(result[:points_redeemed]).to eq(200)
          expect(result[:discount_amount]).to eq(20)
        }.to change(PlatformDiscountCode, :count).by(1)
         .and change(PlatformLoyaltyTransaction, :count).by(1)
         .and change { business_with_points.reload.platform_loyalty_points }.by(-200)
      end
    end
    
    context 'with insufficient points' do
      it 'returns error' do
        business = create(:business, platform_loyalty_points: 50)
        
        result = PlatformLoyaltyService.redeem_loyalty_points(business, 100)
        
        expect(result[:success]).to be false
        expect(result[:error]).to eq('Insufficient loyalty points')
      end
    end
    
    context 'with invalid point amounts' do
      it 'rejects non-100 multiples' do
        result = PlatformLoyaltyService.redeem_loyalty_points(business_with_points, 150)
        
        expect(result[:success]).to be false
        expect(result[:error]).to eq('Points must be in multiples of 100')
      end
      
      it 'rejects amounts over 1000' do
        result = PlatformLoyaltyService.redeem_loyalty_points(business_with_points, 1100)
        
        expect(result[:success]).to be false
        expect(result[:error]).to eq('Maximum 1000 points can be redeemed at once')
      end
    end
  end
  
  describe '.validate_platform_discount_code' do
    let(:business) { create(:business) }
    
    context 'with valid active code' do
      let!(:discount_code) do
        create(:platform_discount_code, 
               code: 'BIZBLASTS-TEST123',
               business: business,
               status: 'active',
               discount_amount: 25,
               points_redeemed: 250)
      end
      
      it 'returns validation success' do
        result = PlatformLoyaltyService.validate_platform_discount_code('BIZBLASTS-TEST123')
        
        expect(result[:valid]).to be true
        expect(result[:discount_code]).to eq(discount_code)
        expect(result[:discount_amount]).to eq(25)
        expect(result[:description]).to include('$25 off')
      end
    end
    
    context 'with referral discount code' do
      let!(:discount_code) do
        create(:platform_discount_code, 
               code: 'BIZBLASTS-REFERRAL-ABC123',
               business: business,
               status: 'active',
               discount_amount: 50,
               points_redeemed: 0) # Referral reward
      end
      
      it 'returns validation with percentage description' do
        result = PlatformLoyaltyService.validate_platform_discount_code('BIZBLASTS-REFERRAL-ABC123')
        
        expect(result[:valid]).to be true
        expect(result[:description]).to include('50% off first month')
      end
    end
    
    context 'with invalid code' do
      it 'returns error for non-existent code' do
        result = PlatformLoyaltyService.validate_platform_discount_code('INVALID-CODE')
        
        expect(result[:valid]).to be false
        expect(result[:error]).to eq('Invalid discount code')
      end
    end
    
    context 'with used code' do
      let!(:discount_code) do
        create(:platform_discount_code, 
               code: 'BIZBLASTS-USED123',
               business: business,
               status: 'used')
      end
      
      it 'returns error for used code' do
        result = PlatformLoyaltyService.validate_platform_discount_code('BIZBLASTS-USED123')
        
        expect(result[:valid]).to be false
        expect(result[:error]).to eq('Discount code has already been used')
      end
    end
  end
  
  describe '.apply_platform_discount_to_stripe_session' do
    let(:business) { create(:business) }
    let(:discount_code) do
      create(:platform_discount_code,
             business: business,
             status: 'active',
             stripe_coupon_id: 'coupon_test_123')
    end
    
    it 'adds discount to Stripe session parameters' do
      session_params = {
        payment_method_types: ['card'],
        mode: 'payment'
      }
      
      result = PlatformLoyaltyService.apply_platform_discount_to_stripe_session(
        discount_code, 
        session_params
      )
      
      expect(result[:discounts]).to eq([{ coupon: 'coupon_test_123' }])
      expect(discount_code.reload.status).to eq('used')
    end
    
    it 'returns unchanged params for invalid code' do
      session_params = {
        payment_method_types: ['card'],
        mode: 'payment'
      }
      
      result = PlatformLoyaltyService.apply_platform_discount_to_stripe_session(
        nil, 
        session_params
      )
      
      expect(result).to eq(session_params)
      expect(result[:discounts]).to be_nil
    end
  end
  
  describe '.platform_loyalty_summary' do
    let(:business) { create(:business) }
    
    before do
      # Create some test data using the proper method that updates cached points
      business.add_platform_loyalty_points!(100, 'Test earned points', nil)
      business.redeem_platform_loyalty_points!(50, 'Test redeemed points')
      create(:platform_referral, 
             referrer_business: business, 
             status: 'qualified')
    end
    
    it 'returns comprehensive loyalty analytics' do
      result = PlatformLoyaltyService.platform_loyalty_summary(business)
      
      expect(result).to include(
        current_points: 50,
        total_earned: 100,
        total_redeemed: 50,
        total_referrals_made: 1,
        qualified_referrals: 1,
        available_redemptions: be_an(Array)
      )
    end
  end
end 