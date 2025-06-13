require 'rails_helper'

RSpec.describe LoyaltyPointsService, type: :service do
  let(:business) { create(:business) }
  let(:loyalty_program) { create(:loyalty_program, business: business, active: true) }
  let(:user) { create(:user, :client, email: 'customer@test.com') }
  let(:tenant_customer) { create(:tenant_customer, business: business, email: user.email) }
  let(:service_obj) { create(:service, business: business, price: 100) }
  let(:booking) { create(:booking, business: business, tenant_customer: tenant_customer, service: service_obj, amount: 100) }
  let(:order) { create(:order, business: business, tenant_customer: tenant_customer, total_amount: 150) }

  before do
    ActsAsTenant.current_tenant = business
    business.update!(
      loyalty_program_enabled: true,
      points_per_dollar: 1.0,
      points_per_service: 5,
      points_per_product: 2
    )
  end

  after do
    # Clear Rails cache to prevent test interference
    Rails.cache.clear
  end

  describe '.award_booking_points' do
    context 'when loyalty program is active' do
      it 'awards points based on booking amount and fixed booking points' do
        expect {
          LoyaltyPointsService.award_booking_points(booking)
        }.to change { LoyaltyTransaction.count }.by(1)

        transaction = LoyaltyTransaction.last
        expect(transaction.tenant_customer).to eq(tenant_customer)
        expect(transaction.transaction_type).to eq('earned')
        expect(transaction.related_booking).to eq(booking)
        expect(transaction.description).to include('booking')
        
        # Points = (amount * points_per_dollar) + points_per_service
        expected_points = (booking.amount * 1.0).to_i + 5
        expect(transaction.points_amount).to eq(expected_points)
      end

      it 'handles bookings with zero amount' do
        booking.update!(amount: 0)
        
        expect {
          LoyaltyPointsService.award_booking_points(booking)
        }.to change { LoyaltyTransaction.count }.by(1)

        transaction = LoyaltyTransaction.last
        expect(transaction.points_amount).to eq(5) # points_per_service
      end

      it 'does not award points if loyalty program is disabled' do
        business.update!(loyalty_program_enabled: false)
        
        expect {
          LoyaltyPointsService.award_booking_points(booking)
        }.not_to change { LoyaltyTransaction.count }
      end

      it 'does not award points if loyalty program is inactive' do
        business.update!(loyalty_program_enabled: false)
        
        expect {
          LoyaltyPointsService.award_booking_points(booking)
        }.not_to change { LoyaltyTransaction.count }
      end

      it 'does not award duplicate points for the same booking' do
        LoyaltyPointsService.award_booking_points(booking)
        
        expect {
          LoyaltyPointsService.award_booking_points(booking)
        }.not_to change { LoyaltyTransaction.count }
      end
    end
  end

  describe '.award_order_points' do
    context 'when loyalty program is active' do
      it 'awards points based on order total amount' do
        expect {
          LoyaltyPointsService.award_order_points(order)
        }.to change { LoyaltyTransaction.count }.by(1)

        transaction = LoyaltyTransaction.last
        expect(transaction.tenant_customer).to eq(tenant_customer)
        expect(transaction.transaction_type).to eq('earned')
        expect(transaction.related_order).to eq(order)
        expect(transaction.description).to include('order')
        
        expected_points = (order.total_amount * 1.0).to_i
        expect(transaction.points_amount).to eq(expected_points)
      end

      it 'handles orders with zero amount' do
        order.update!(
          total_amount: 0,
          shipping_method: nil,
          tax_rate: nil,
          shipping_amount: 0,
          tax_amount: 0
        )
        
        expect {
          LoyaltyPointsService.award_order_points(order)
        }.not_to change { LoyaltyTransaction.count }
      end

      it 'does not award points if loyalty program is disabled' do
        business.update!(loyalty_program_enabled: false)
        
        expect {
          LoyaltyPointsService.award_order_points(order)
        }.not_to change { LoyaltyTransaction.count }
      end

      it 'does not award duplicate points for the same order' do
        LoyaltyPointsService.award_order_points(order)
        
        expect {
          LoyaltyPointsService.award_order_points(order)
        }.not_to change { LoyaltyTransaction.count }
      end
    end
  end

  describe '.award_referral_points' do
    let(:referrer_user) { create(:user, :client, email: 'referrer@example.com') }
    let(:referred_user) { create(:user, :client, email: 'referred@example.com') }
    let(:referrer_customer) { create(:tenant_customer, business: business, email: referrer_user.email) }
    let(:referred_customer) { create(:tenant_customer, business: business, email: referred_user.email) }
    let(:referral) { create(:referral, business: business, referrer: referrer_user, referred_tenant_customer: referred_customer, status: 'qualified') }

    context 'when loyalty program is active' do
      it 'awards referral points to the referrer' do
        referrer_customer # Create the customer record
        
        expect {
          LoyaltyPointsService.award_referral_points(referral)
        }.to change { LoyaltyTransaction.count }.by(1)

        transaction = LoyaltyTransaction.last
        expect(transaction.tenant_customer).to eq(referrer_customer)
        expect(transaction.transaction_type).to eq('earned')
        expect(transaction.related_referral).to eq(referral)
        expect(transaction.description).to include('Referral')
        expect(transaction.points_amount).to be > 0
      end

      it 'does not award points if loyalty program is disabled' do
        business.update!(loyalty_program_enabled: false)
        
        expect {
          LoyaltyPointsService.award_referral_points(referral)
        }.not_to change { LoyaltyTransaction.count }
      end

      it 'does not award duplicate points for the same referral' do
        LoyaltyPointsService.award_referral_points(referral)
        
        expect {
          LoyaltyPointsService.award_referral_points(referral)
        }.not_to change { LoyaltyTransaction.count }
      end
    end
  end

  describe '.redeem_points' do
    let!(:earned_transaction) { create(:loyalty_transaction, 
                                      tenant_customer: tenant_customer, 
                                      transaction_type: 'earned', 
                                      points_amount: 500) }

    context 'when customer has sufficient points' do
      before do
        # Mock Stripe coupon creation
        allow(Stripe::Coupon).to receive(:create).and_return(
          double('coupon', id: 'test_coupon_123', amount_off: 1000, currency: 'usd')
        )
      end

      it 'creates redemption transaction and discount code' do
        result = LoyaltyPointsService.redeem_points(tenant_customer, 100, 'Test redemption')
        
        expect(result[:success]).to be true
        expect(result[:discount_code]).to be_present
        
        # Check redemption transaction was created
        redemption = LoyaltyTransaction.redeemed.last
        expect(redemption.tenant_customer).to eq(tenant_customer)
        expect(redemption.points_amount).to eq(-100)
        expect(redemption.description).to eq('Test redemption')
        
        # Check discount code was created
        discount_code = DiscountCode.last
        expect(discount_code.business).to eq(business)
        expect(discount_code.used_by_customer).to eq(tenant_customer)
        expect(discount_code.discount_value).to eq(10.0)
        expect(discount_code.active).to be true
      end

      it 'calculates correct discount amount' do
        result = LoyaltyPointsService.redeem_points(tenant_customer, 200, 'Test redemption')
        
        discount_code = DiscountCode.last
        expected_discount = (200 / 10.0).round(2) # Default: 10 points = $1
        expect(discount_code.discount_value).to eq(expected_discount)
      end

      it 'handles Stripe errors gracefully' do
        allow(Stripe::Coupon).to receive(:create).and_raise(Stripe::StripeError.new('Test error'))
        
        result = LoyaltyPointsService.redeem_points(tenant_customer, 100, 'Test redemption')
        
        expect(result[:success]).to be false
        expect(result[:error]).to include('Stripe error')
        
        # Should not create transactions or discount codes on Stripe failure
        expect(LoyaltyTransaction.redeemed.count).to eq(0)
        expect(DiscountCode.count).to eq(0)
      end
    end

    context 'when customer has insufficient points' do
      it 'returns error without creating transactions' do
        result = LoyaltyPointsService.redeem_points(tenant_customer, 600, 'Test redemption')
        
        expect(result[:success]).to be false
        expect(result[:error]).to include('Insufficient points')
        
        expect(LoyaltyTransaction.redeemed.count).to eq(0)
        expect(DiscountCode.count).to eq(0)
      end
    end

    context 'when loyalty program is disabled' do
      it 'returns error' do
        business.update!(loyalty_program_enabled: false)
        
        result = LoyaltyPointsService.redeem_points(tenant_customer, 100, 'Test redemption')
        
        expect(result[:success]).to be false
        expect(result[:error]).to include('not active')
      end
    end
  end

  describe '.calculate_customer_balance' do
    before do
      create(:loyalty_transaction, tenant_customer: tenant_customer, transaction_type: 'earned', points_amount: 100)
      create(:loyalty_transaction, tenant_customer: tenant_customer, transaction_type: 'earned', points_amount: 50)
      create(:loyalty_transaction, tenant_customer: tenant_customer, transaction_type: 'redeemed', points_amount: -30)
    end

    it 'calculates correct balance' do
      balance = LoyaltyPointsService.calculate_customer_balance(tenant_customer)
      expect(balance).to eq(120) # 100 + 50 - 30
    end

    it 'returns zero for customer with no transactions' do
      # Ensure we're in the correct tenant context
      ActsAsTenant.current_tenant = business
      
      # Create a completely separate user and customer to avoid any data leakage
      other_user = create(:user, :client, email: 'isolated@test.com')
      other_customer = create(:tenant_customer, business: business, email: other_user.email)
      
      # Clear any cached loyalty points to avoid test interference
      other_customer.clear_loyalty_cache
      
      # Ensure we're calculating only for this specific customer
      balance = LoyaltyPointsService.calculate_customer_balance(other_customer)
      expect(balance).to eq(0)
      
      # Double-check that this customer has no transactions
      expect(LoyaltyTransaction.where(tenant_customer: other_customer).count).to eq(0)
    end
  end

  describe '.get_redemption_options' do
    let!(:earned_transaction) { create(:loyalty_transaction, 
                                      tenant_customer: tenant_customer, 
                                      transaction_type: 'earned', 
                                      points_amount: 500) }

    it 'returns available redemption options based on balance' do
      options = LoyaltyPointsService.get_redemption_options(tenant_customer)
      
      expect(options).to be_an(Array)
      expect(options.length).to be > 0
      
      # Should only include options customer can afford
      options.each do |option|
        expect(option[:points]).to be <= 500
        expect(option[:discount_amount]).to be > 0
        expect(option[:description]).to be_present
      end
    end

    it 'returns empty array for customer with no points' do
      # Ensure we're in the correct tenant context
      ActsAsTenant.current_tenant = business
      
      # Create a completely separate user and customer to avoid any data leakage
      isolated_user = create(:user, :client, email: 'isolated_redemption@test.com')
      isolated_customer = create(:tenant_customer, business: business, email: isolated_user.email)
      
      # Clear any cached loyalty points to avoid test interference
      isolated_customer.clear_loyalty_cache
      
      # Verify this customer has no points
      balance = LoyaltyPointsService.calculate_customer_balance(isolated_customer)
      expect(balance).to eq(0)
      
      options = LoyaltyPointsService.get_redemption_options(isolated_customer)
      
      expect(options).to eq([])
    end
  end

  describe '.expire_points' do
    let!(:old_transaction) { create(:loyalty_transaction, 
                                   tenant_customer: tenant_customer, 
                                   transaction_type: 'earned', 
                                   points_amount: 100,
                                   expires_at: 1.day.ago) }
    let!(:valid_transaction) { create(:loyalty_transaction, 
                                     tenant_customer: tenant_customer, 
                                     transaction_type: 'earned', 
                                     points_amount: 50,
                                     expires_at: 1.day.from_now) }

    it 'expires points that have passed expiration date' do
      expect {
        LoyaltyPointsService.expire_points
      }.to change { LoyaltyTransaction.expired.count }.by(1)

      expired_transaction = LoyaltyTransaction.expired.last
      expect(expired_transaction.tenant_customer).to eq(tenant_customer)
      expect(expired_transaction.points_amount).to eq(-100)
      expect(expired_transaction.description).to include('expired')
    end

    it 'does not expire points that are still valid' do
      LoyaltyPointsService.expire_points
      
      # Should not create expiration for valid transaction
      expired_transactions = LoyaltyTransaction.expired.where(
        'description LIKE ? AND points_amount = ?', 
        '%expired%', 
        -50
      )
      expect(expired_transactions.count).to eq(0)
    end
  end

  describe 'tenant scoping' do
    let(:other_business) { create(:business) }
    let(:other_user) { create(:user, :client, email: 'other@test.com') }
    let(:other_customer) { create(:tenant_customer, business: other_business, email: other_user.email) }
    let(:other_booking) { create(:booking, business: other_business, tenant_customer: other_customer) }

    it 'only affects current tenant data' do
      ActsAsTenant.current_tenant = other_business
      other_business.update!(
        loyalty_program_enabled: true,
        points_per_dollar: 1.0,
        points_per_service: 5,
        points_per_product: 2
      )
      create(:loyalty_program, business: other_business, active: true)
      other_booking.update!(amount: 100)
      
      expect {
        LoyaltyPointsService.award_booking_points(other_booking)
      }.to change { LoyaltyTransaction.count }.by(1)

      ActsAsTenant.current_tenant = business
      
      # Should not see other tenant's transactions
      expect(LoyaltyTransaction.count).to eq(0)
    end
  end
end 