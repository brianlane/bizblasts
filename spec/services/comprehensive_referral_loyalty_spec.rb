# Comprehensive Referral and Loyalty System Test Scenarios
require 'rails_helper'

RSpec.describe 'Comprehensive Referral and Loyalty System', type: :service do
  # Setup common fixtures
  let!(:business_x) do
    create(:business, name: 'Business X', hostname: 'businessx').tap do |b|
      b.update!(
        loyalty_program_enabled: true,
        referral_program_enabled: true,
        points_per_dollar: 1.0,
        points_per_service: 5,
        points_per_product: 2
      )
      # Create referral program
      b.create_referral_program!(
        active: true,
        referrer_reward_type: 'points',
        referrer_reward_value: 100,
        referral_code_discount_amount: 10.0,
        min_purchase_amount: 0.0
      )
    end
  end
  
  let!(:business_y) do
    create(:business, name: 'Business Y', hostname: 'businessy').tap do |b|
      b.update!(
        loyalty_program_enabled: true,
        referral_program_enabled: true,
        points_per_dollar: 2.0,
        points_per_service: 10,
        points_per_product: 3
      )
      # Create referral program
      b.create_referral_program!(
        active: true,
        referrer_reward_type: 'points',
        referrer_reward_value: 150,
        referral_code_discount_amount: 15.0,
        min_purchase_amount: 0.0
      )
    end
  end
  
  let!(:business_z) do
    create(:business, name: 'Business Z', hostname: 'businessz').tap do |b|
      b.update!(loyalty_program_enabled: false, referral_program_enabled: false)
    end
  end
  
  let!(:client_user_a) { create(:user, :client, first_name: 'Alice', last_name: 'Smith', email: 'alice@example.com') }
  let!(:client_user_b) { create(:user, :client, first_name: 'Bob', last_name: 'Jones', email: 'bob@example.com') }
  
  let!(:service_x) { create(:service, business: business_x, price: 100.00, name: 'Haircut') }
  let!(:product_x) { create(:product, business: business_x, price: 50.00) }
  let!(:product_variant_x) { create(:product_variant, product: product_x, price_modifier: 0.00) }
  let!(:staff_member_x) { create(:staff_member, business: business_x) }
  
  let!(:service_y) { create(:service, business: business_y, price: 80.00, name: 'Massage') }
  let!(:product_y) { create(:product, business: business_y, price: 40.00) }
  let!(:product_variant_y) { create(:product_variant, product: product_y, price_modifier: 0.00) }
  let!(:staff_member_y) { create(:staff_member, business: business_y) }

  before do
    ActsAsTenant.current_tenant = business_x
  end

  after do
    ActsAsTenant.current_tenant = nil
  end

  describe '1. Client User A Referral Code Scenarios' do
    let!(:tenant_customer_a_x) { create(:tenant_customer, business: business_x, email: client_user_a.email) }
    let!(:referral_a_x) { create(:referral, business: business_x, referrer: client_user_a, referred_tenant_customer: tenant_customer_a_x) }
    let(:referral_code_a_x) { referral_a_x.referral_code }

    describe 'A. Client user A uses their own referral code for a service at business X' do
      it 'works and creates discount for self-referral' do
        ActsAsTenant.with_tenant(business_x) do
          # Create booking with referral code
          booking = create(:booking,
            business: business_x,
            tenant_customer: tenant_customer_a_x,
            service: service_x,
            staff_member: staff_member_x,
            amount: service_x.price,
            applied_promo_code: referral_code_a_x,
            promo_code_type: 'referral'
          )
          
          # Apply referral code through service
          result = PromoCodeService.apply_code(referral_code_a_x, business_x, booking, tenant_customer_a_x)
          
          expect(result[:success]).to be true
          expect(result[:type]).to eq('referral')
          
          booking.reload
          expect(booking.applied_promo_code).to eq(referral_code_a_x)
          expect(booking.promo_code_type).to eq('referral')
          expect(booking.promo_discount_amount).to be > 0
        end
      end
    end

    describe 'B. Client user B uses the code for a product at business X' do
      it 'works and awards loyalty points to both users' do
        tenant_customer_b = create(:tenant_customer, business: business_x, email: client_user_b.email)
        
        ActsAsTenant.with_tenant(business_x) do
          # Create order with referral code
          order = create(:order,
            business: business_x,
            tenant_customer: tenant_customer_b,
            total_amount: product_variant_x.final_price,
            applied_promo_code: referral_code_a_x,
            promo_code_type: 'referral'
          )
          
          # Create line item
          create(:line_item,
            lineable: order,
            product_variant: product_variant_x,
            quantity: 1,
            price: product_variant_x.final_price,
            total_amount: product_variant_x.final_price
          )
          
          # Apply referral code
          result = PromoCodeService.apply_code(referral_code_a_x, business_x, order, tenant_customer_b)
          
          expect(result[:success]).to be true
          expect(result[:type]).to eq('referral')
          
          # Check that referral was processed and rewarded (this happens automatically in apply_code)
          qualified_referral = Referral.find_by(referral_code: referral_code_a_x)
          expect(qualified_referral).to be_present
          expect(qualified_referral.status).to eq('rewarded')
          
          # Award loyalty points for the order
          LoyaltyPointsService.award_order_points(order)
          
          # Check that both users get loyalty points
          referrer_customer = TenantCustomer.find_by(business: business_x, email: client_user_a.email) ||
                             create(:tenant_customer, business: business_x, email: client_user_a.email)
          
          expect(LoyaltyTransaction.exists?(tenant_customer: referrer_customer, transaction_type: 'earned', related_referral: qualified_referral)).to be true
          expect(LoyaltyTransaction.exists?(tenant_customer: tenant_customer_b, transaction_type: 'earned')).to be true
        end
      end
    end

    describe 'C. A tenant customer uses the code for a product and a service at business X' do
      it 'works for existing tenant customer' do
        tenant_user_c = create(:user, :client, email: 'tenant@example.com', first_name: 'Tenant', last_name: 'Customer')
        tenant_customer_c = create(:tenant_customer, business: business_x, email: 'tenant@example.com')
        
        ActsAsTenant.with_tenant(business_x) do
          # Create order with both product and service
          order = create(:order,
            business: business_x,
            tenant_customer: tenant_customer_c,
            order_type: 'mixed',
            total_amount: product_variant_x.final_price + service_x.price,
            applied_promo_code: referral_code_a_x,
            promo_code_type: 'referral'
          )
          
          # Create line items for both product and service
          create(:line_item,
            lineable: order,
            product_variant: product_variant_x,
            quantity: 1,
            price: product_variant_x.final_price,
            total_amount: product_variant_x.final_price
          )
          
          create(:line_item,
            lineable: order,
            product_variant: nil,
            service: service_x,
            staff_member: staff_member_x,
            quantity: 1,
            price: service_x.price,
            total_amount: service_x.price
          )
          
          # Apply referral code
          result = PromoCodeService.apply_code(referral_code_a_x, business_x, order, tenant_customer_c)
          
          expect(result[:success]).to be true
          expect(result[:type]).to eq('referral')
          
          # Award loyalty points
          LoyaltyPointsService.award_order_points(order)
          
          # Check loyalty points were awarded
          expect(LoyaltyTransaction.exists?(tenant_customer: tenant_customer_c, transaction_type: 'earned')).to be true
        end
      end

      it 'works when creating account during checkout' do
        ActsAsTenant.with_tenant(business_x) do
          # Simulate creating customer during checkout
          new_user = create(:user, :client, email: 'newcustomer@example.com', first_name: 'New', last_name: 'Customer')
          new_customer = TenantCustomer.create!(
            business: business_x,
            email: 'newcustomer@example.com',
            name: 'New Customer'
          )
          
          order = create(:order,
            business: business_x,
            tenant_customer: new_customer,
            order_type: 'mixed',
            total_amount: product_variant_x.final_price + service_x.price,
            applied_promo_code: referral_code_a_x,
            promo_code_type: 'referral'
          )
          
          # Create line items for the order so loyalty points can be calculated
          create(:line_item,
            lineable: order,
            product_variant: product_variant_x,
            quantity: 1,
            price: product_variant_x.final_price,
            total_amount: product_variant_x.final_price
          )
          
          create(:line_item,
            lineable: order,
            product_variant: nil,
            service: service_x,
            staff_member: staff_member_x,
            quantity: 1,
            price: service_x.price,
            total_amount: service_x.price
          )
          
          # Apply referral code and award points
          result = PromoCodeService.apply_code(referral_code_a_x, business_x, order, new_customer)
          
          expect(result[:success]).to be true
          
          LoyaltyPointsService.award_order_points(order)
          
          # Customer should get loyalty points
          expect(LoyaltyTransaction.exists?(tenant_customer: new_customer, transaction_type: 'earned')).to be true
        end
      end
    end

    describe 'D. All scenarios with business running a promotion for certain items' do
      let!(:promotion_x) { create(:promotion, :automatic, business: business_x, discount_type: 'percentage', discount_value: 20, applicable_to_products: true, applicable_to_services: true) }
      
      before do
        # Associate promotion with specific items
        promotion_x.promotion_products.create!(product: product_x)
        promotion_x.promotion_services.create!(service: service_x)
      end

      it 'allows stacking referral code with business promotion' do
        ActsAsTenant.with_tenant(business_x) do
          # Check that promotional pricing is automatically applied
          expect(product_x.on_promotion?).to be true
          expect(product_x.promotional_price).to eq(40.00) # 50 - 20% = 40
          expect(product_x.promotion_display_text).to eq('20% OFF')
          
          expect(service_x.on_promotion?).to be true
          expect(service_x.promotional_price).to eq(80.00) # 100 - 20% = 80
          expect(service_x.promotion_display_text).to eq('20% OFF')
          
          # Test with mixed order using promotional pricing
          tenant_customer = create(:tenant_customer, business: business_x, email: client_user_b.email)
          
          order = create(:order,
            business: business_x,
            tenant_customer: tenant_customer,
            order_type: 'mixed',
            total_amount: product_x.promotional_price + service_x.promotional_price, # Use promotional prices
            applied_promo_code: referral_code_a_x,
            promo_code_type: 'referral'
          )
          
          # Create line items using promotional pricing
          create(:line_item,
            lineable: order,
            product_variant: product_variant_x,
            quantity: 1,
            price: product_x.promotional_price, # Promotional price
            total_amount: product_x.promotional_price
          )
          
          create(:line_item,
            lineable: order,
            product_variant: nil,
            service: service_x,
            staff_member: staff_member_x,
            quantity: 1,
            price: service_x.promotional_price, # Promotional price
            total_amount: service_x.promotional_price
          )
          
          # Apply referral code on top of promotional pricing
          result = PromoCodeService.apply_code(referral_code_a_x, business_x, order, tenant_customer)
          expect(result[:success]).to be true
          expect(result[:type]).to eq('referral')
          
          # Both promotional discount AND referral discount should apply
          order.reload
          expect(order.total_amount).to be < (product_x.promotional_price + service_x.promotional_price)
          
          # Award loyalty points based on promotional pricing
          LoyaltyPointsService.award_order_points(order)
          
          points = LoyaltyTransaction.where(tenant_customer: tenant_customer, transaction_type: 'earned').sum(:points_amount)
          expect(points).to be > 0
        end
      end
      
      it 'shows promotional pricing on product and service views' do
        ActsAsTenant.with_tenant(business_x) do
          # Test that products show promotional badges and pricing
          expect(product_x.current_promotion).to eq(promotion_x)
          expect(product_x.on_promotion?).to be true
          expect(product_x.promotional_price).to eq(40.00)
          expect(product_x.promotion_discount_amount).to eq(10.00)
          expect(product_x.savings_percentage).to eq(20)
          expect(product_x.promotion_display_text).to eq('20% OFF')
          
          # Test that services show promotional badges and pricing
          expect(service_x.current_promotion).to eq(promotion_x)
          expect(service_x.on_promotion?).to be true
          expect(service_x.promotional_price).to eq(80.00)
          expect(service_x.promotion_discount_amount).to eq(20.00)
          expect(service_x.savings_percentage).to eq(20)
          expect(service_x.promotion_display_text).to eq('20% OFF')
        end
      end
      
      it 'handles promotion expiration and usage limits' do
        ActsAsTenant.with_tenant(business_x) do
          # Test with expired promotion
          promotion_x.update!(end_date: 1.week.ago)
          expect(product_x.on_promotion?).to be false
          expect(product_x.promotional_price).to eq(50.00) # Back to original price
          
          # Reset and test usage limit
          promotion_x.update!(end_date: 1.week.from_now, usage_limit: 1, current_usage: 1)
          expect(product_x.on_promotion?).to be false
          expect(service_x.on_promotion?).to be false
        end
      end
    end

    describe 'E. Client user A uses their own referral code for a service at business Y' do
      it 'fails because referral codes are business-specific' do
        ActsAsTenant.with_tenant(business_y) do
          tenant_customer_a_y = create(:tenant_customer, business: business_y, email: client_user_a.email)
          
          # Try to validate referral code from business X at business Y
          validation = PromoCodeService.validate_code(referral_code_a_x, business_y, tenant_customer_a_y)
          
          expect(validation[:valid]).to be false
          expect(validation[:error]).to include('Invalid')
        end
      end
    end

    describe 'F. Client user B uses the code for a product at business Y' do
      it 'fails because referral codes are business-specific' do
        ActsAsTenant.with_tenant(business_y) do
          tenant_customer_b_y = create(:tenant_customer, business: business_y, email: client_user_b.email)
          
          validation = PromoCodeService.validate_code(referral_code_a_x, business_y, tenant_customer_b_y)
          
          expect(validation[:valid]).to be false
          expect(validation[:error]).to include('Invalid')
        end
      end
    end

    describe 'G. A tenant customer uses the code for a product and service at business Y' do
      it 'fails because referral codes are business-specific' do
        ActsAsTenant.with_tenant(business_y) do
          tenant_customer_y = create(:tenant_customer, business: business_y, email: 'tenant@businessy.com')
          
          validation = PromoCodeService.validate_code(referral_code_a_x, business_y, tenant_customer_y)
          
          expect(validation[:valid]).to be false
          expect(validation[:error]).to include('Invalid')
        end
      end
    end

    describe 'AA. Upon successful stripe payment, client user A gets loyalty points' do
      it 'awards loyalty points after successful payment' do
        ActsAsTenant.with_tenant(business_x) do
          booking = create(:booking,
            business: business_x,
            tenant_customer: tenant_customer_a_x,
            service: service_x,
            staff_member: staff_member_x,
            amount: service_x.price,
            status: 'confirmed'
          )
          
          # Simulate successful payment (payment status is tracked via invoice, not booking)
          
          # Award loyalty points
          LoyaltyPointsService.award_booking_points(booking)
          
          # Check loyalty points were awarded
          total_points = LoyaltyTransaction.where(tenant_customer: tenant_customer_a_x, transaction_type: 'earned').sum(:points_amount)
          expect(total_points).to be > 0
        end
      end
    end

    describe 'BA. Upon successful stripe payment, both client user A and B get loyalty points' do
      it 'awards loyalty points to both referrer and referred user' do
        tenant_customer_b = create(:tenant_customer, business: business_x, email: client_user_b.email)
        
        ActsAsTenant.with_tenant(business_x) do
          # Create booking for user B using user A's referral code
          booking = create(:booking,
            business: business_x,
            tenant_customer: tenant_customer_b,
            service: service_x,
            staff_member: staff_member_x,
            amount: service_x.price,
            applied_promo_code: referral_code_a_x,
            promo_code_type: 'referral',
            status: 'confirmed'
          )
          
          # Apply referral code (this handles referral processing automatically)
          result = PromoCodeService.apply_code(referral_code_a_x, business_x, booking, tenant_customer_b)
          expect(result[:success]).to be true
          expect(result[:type]).to eq('referral')
          
          # Award loyalty points for booking
          LoyaltyPointsService.award_booking_points(booking)
          
          # Check both users got loyalty points
          points_a = LoyaltyTransaction.where(tenant_customer: tenant_customer_a_x, transaction_type: 'earned').sum(:points_amount)
          points_b = LoyaltyTransaction.where(tenant_customer: tenant_customer_b, transaction_type: 'earned').sum(:points_amount)
          
          expect(points_a).to be > 0  # Referral reward
          expect(points_b).to be > 0  # Service purchase reward
        end
      end
    end

    describe 'CA. Upon successful payment, A gets points and tenant customer gets points only if they make account' do
      it 'tenant customer without account does not get loyalty points' do
        # Simulate guest checkout - create guest customer but don't create User account
        ActsAsTenant.with_tenant(business_x) do
          guest_customer = create(:tenant_customer, 
            business: business_x, 
            email: 'guest@example.com',
            name: 'Guest Customer'
          )
          
          guest_booking = create(:booking,
            business: business_x,
            tenant_customer: guest_customer,
            service: service_x,
            staff_member: staff_member_x,
            amount: service_x.price,
            status: 'confirmed'
          )
          
          # Try to award loyalty points (should not work without User account)
          expect {
            LoyaltyPointsService.award_booking_points(guest_booking)
          }.not_to change { LoyaltyTransaction.count }
        end
      end

      it 'tenant customer with account created during checkout gets loyalty points' do
        ActsAsTenant.with_tenant(business_x) do
          # Customer creates account during checkout
          checkout_user = create(:user, :client, email: 'checkout@example.com', first_name: 'Checkout', last_name: 'Customer')
          new_customer = TenantCustomer.create!(
            business: business_x,
            email: 'checkout@example.com',
            name: 'Checkout Customer'
          )
          
          booking = create(:booking,
            business: business_x,
            tenant_customer: new_customer,
            service: service_x,
            staff_member: staff_member_x,
            amount: service_x.price,
            status: 'confirmed'
          )
          
          # Award loyalty points
          LoyaltyPointsService.award_booking_points(booking)
          
          # Check customer got loyalty points
          points = LoyaltyTransaction.where(tenant_customer: new_customer, transaction_type: 'earned').sum(:points_amount)
          expect(points).to be > 0
        end
      end
    end
  end

  describe '2. Business-Generated Discount Code Scenarios' do
    let!(:business_discount_x) do
      ActsAsTenant.with_tenant(business_x) do
        create(:discount_code, 
          business: business_x, 
          code: 'BUSINESS20', 
          discount_type: 'fixed_amount', 
          discount_value: 20,
          used_by_customer: nil, # Allow any customer to use this code
          single_use: false, # Allow multiple uses for testing
          max_usage: 10
        )
      end
    end

    describe 'Client user A uses business discount for a service and gets loyalty points' do
      it 'applies discount and awards loyalty points' do
        tenant_customer_a = create(:tenant_customer, business: business_x, email: client_user_a.email)
        
        ActsAsTenant.with_tenant(business_x) do
          booking = create(:booking,
            business: business_x,
            tenant_customer: tenant_customer_a,
            service: service_x,
            staff_member: staff_member_x,
            amount: service_x.price,
            applied_promo_code: 'BUSINESS20',
            promo_code_type: 'discount'
          )
          
          # Apply discount code
          result = PromoCodeService.apply_code('BUSINESS20', business_x, booking, tenant_customer_a)
          
          expect(result[:success]).to be true
          expect(result[:type]).to eq('discount')
          
          # Award loyalty points (should be based on original amount, not discounted)
          LoyaltyPointsService.award_booking_points(booking)
          
          points = LoyaltyTransaction.where(tenant_customer: tenant_customer_a, transaction_type: 'earned').sum(:points_amount)
          expect(points).to be > 0
        end
      end
    end

    describe 'Client user B uses business discount for a product and gets loyalty points' do
      it 'applies discount and awards loyalty points' do
        tenant_customer_b = create(:tenant_customer, business: business_x, email: client_user_b.email)
        
        ActsAsTenant.with_tenant(business_x) do
          order = create(:order,
            business: business_x,
            tenant_customer: tenant_customer_b,
            total_amount: product_variant_x.final_price,
            applied_promo_code: 'BUSINESS20',
            promo_code_type: 'discount'
          )
          
          create(:line_item,
            lineable: order,
            product_variant: product_variant_x,
            quantity: 1,
            price: product_variant_x.final_price,
            total_amount: product_variant_x.final_price
          )
          
          # Apply discount code
          result = PromoCodeService.apply_code('BUSINESS20', business_x, order, tenant_customer_b)
          
          expect(result[:success]).to be true
          
          # Award loyalty points
          LoyaltyPointsService.award_order_points(order)
          
          points = LoyaltyTransaction.where(tenant_customer: tenant_customer_b, transaction_type: 'earned').sum(:points_amount)
          expect(points).to be > 0
        end
      end
    end

    describe 'Tenant customer scenarios' do
      it 'works without account creation and no loyalty points' do
        ActsAsTenant.with_tenant(business_x) do
          # Guest checkout - create guest customer but don't link to user account
          guest_customer = create(:tenant_customer, 
            business: business_x, 
            email: 'guest@example.com',
            name: 'Guest Customer'
          )
          
          booking = create(:booking,
            business: business_x,
            tenant_customer: guest_customer,
            service: service_x,
            staff_member: staff_member_x,
            amount: service_x.price,
            applied_promo_code: 'BUSINESS20',
            promo_code_type: 'discount'
          )
          
          # Discount should apply but no loyalty points without customer account
          expect(booking.applied_promo_code).to eq('BUSINESS20')
          
          expect {
            LoyaltyPointsService.award_booking_points(booking)
          }.not_to change { LoyaltyTransaction.count }
        end
      end

      it 'grants loyalty points when account created at checkout' do
        ActsAsTenant.with_tenant(business_x) do
          new_account_user = create(:user, :client, email: 'newaccount@example.com', first_name: 'New', last_name: 'Account')
          customer = TenantCustomer.create!(
            business: business_x,
            email: 'newaccount@example.com',
            name: 'New Account Customer'
          )
          
          booking = create(:booking,
            business: business_x,
            tenant_customer: customer,
            service: service_x,
            staff_member: staff_member_x,
            amount: service_x.price,
            applied_promo_code: 'BUSINESS20',
            promo_code_type: 'discount'
          )
          
          # Apply discount and award points
          PromoCodeService.apply_code('BUSINESS20', business_x, booking, customer)
          LoyaltyPointsService.award_booking_points(booking)
          
          points = LoyaltyTransaction.where(tenant_customer: customer, transaction_type: 'earned').sum(:points_amount)
          expect(points).to be > 0
        end
      end
    end

    describe 'Business promotion scenarios' do
      let!(:promotion_x) { create(:promotion, :code_based, business: business_x, code: 'PROMO15', discount_type: 'percentage', discount_value: 15) }

      it 'allows stacking business discount with promotion' do
        stacking_user = create(:user, :client, email: 'stacking@example.com', first_name: 'Stacking', last_name: 'User')
        tenant_customer = create(:tenant_customer, business: business_x, email: 'stacking@example.com')
        
        ActsAsTenant.with_tenant(business_x) do
          # Create mixed order to ensure invoice is created
          order = create(:order,
            business: business_x,
            tenant_customer: tenant_customer,
            order_type: 'mixed',
            total_amount: product_variant_x.final_price + service_x.price,
            applied_promo_code: 'BUSINESS20',
            promo_code_type: 'discount'
          )
          
          # Add line items for both product and service
          create(:line_item,
            lineable: order,
            product_variant: product_variant_x,
            quantity: 1,
            price: product_variant_x.final_price,
            total_amount: product_variant_x.final_price
          )
          
          create(:line_item,
            lineable: order,
            product_variant: nil,
            service: service_x,
            staff_member: staff_member_x,
            quantity: 1,
            price: service_x.price,
            total_amount: service_x.price
          )
          
          # Reload order to ensure invoice is created
          order.reload
          
          # Apply business discount
          discount_result = PromoCodeService.apply_code('BUSINESS20', business_x, order, tenant_customer)
          expect(discount_result[:success]).to be true
          
          # Apply promotion to invoice
          promotion_result = PromotionManager.apply_promotion_to_invoice(order.invoice, 'PROMO15')
          expect(promotion_result[:valid]).to be true
          
          # Award loyalty points
          LoyaltyPointsService.award_order_points(order)
          
          points = LoyaltyTransaction.where(tenant_customer: tenant_customer, transaction_type: 'earned').sum(:points_amount)
          expect(points).to be > 0
        end
      end
    end

    describe 'Cross-business scenarios fail' do
      it 'business Y discount code fails at business X' do
        business_discount_y = create(:discount_code, business: business_y, code: 'BUSINESSY10', discount_type: 'fixed_amount', discount_value: 10)
        
        ActsAsTenant.with_tenant(business_x) do
          tenant_customer = create(:tenant_customer, business: business_x, email: 'crosstest@example.com')
          
          validation = PromoCodeService.validate_code('BUSINESSY10', business_x, tenant_customer)
          
          expect(validation[:valid]).to be false
          expect(validation[:error]).to include('Invalid')
        end
      end
    end
  end

  describe '3. Loyalty Reward Redemption Scenarios' do
    describe 'Client user has enough loyalty points to get a loyalty reward' do
      let!(:rewards_user) { create(:user, :client, email: 'rewards@example.com', first_name: 'Rewards', last_name: 'User') }
      let!(:tenant_customer_rewards) { create(:tenant_customer, business: business_x, email: 'rewards@example.com') }
      
      before do
        # Mock Stripe API calls for loyalty redemptions
        allow(Stripe::Coupon).to receive(:create).and_return(
          double('Stripe::Coupon', id: 'coupon_test_loyalty_123')
        )
        
        ActsAsTenant.with_tenant(business_x) do
          # Give customer 500 loyalty points
          create(:loyalty_transaction,
            tenant_customer: tenant_customer_rewards,
            business: business_x,
            points_amount: 500,
            transaction_type: 'earned',
            description: 'Initial points'
          )
        end
      end

      it 'successfully redeems points for discount code and uses it' do
        ActsAsTenant.with_tenant(business_x) do
          # Redeem 100 points for $10 discount
          redemption_result = LoyaltyPointsService.redeem_points(tenant_customer_rewards, 100, "Test redemption")
          
          expect(redemption_result[:success]).to be true
          expect(redemption_result[:discount_code]).to be_present
          
          discount_code = redemption_result[:discount_code]
          
          # Use the loyalty discount code for a service
          booking = create(:booking,
            business: business_x,
            tenant_customer: tenant_customer_rewards,
            service: service_x,
            staff_member: staff_member_x,
            amount: service_x.price,
            applied_promo_code: discount_code,
            promo_code_type: 'loyalty'
          )
          
          # Apply the loyalty code
          result = PromoCodeService.apply_code(discount_code, business_x, booking, tenant_customer_rewards)
          
          expect(result[:success]).to be true
          expect(result[:type]).to eq('loyalty')
          
          # Customer should still earn points for the booking (minus the redeemed points)
          LoyaltyPointsService.award_booking_points(booking)
          
          # Check final point balance
          final_balance = LoyaltyTransaction.total_earned_for_customer(tenant_customer_rewards) - 
                         LoyaltyTransaction.total_redeemed_for_customer(tenant_customer_rewards)
          
          expected_points = business_x.calculate_loyalty_points(service_x.price, service: service_x)
          expect(final_balance).to eq(400 + expected_points) # 500 - 100 + new points
        end
      end

      it 'works with all scenarios from business discount section' do
        ActsAsTenant.with_tenant(business_x) do
          # Redeem points for discount code
          redemption_result = LoyaltyPointsService.redeem_points(tenant_customer_rewards, 200, "Test redemption")
          loyalty_code = redemption_result[:discount_code]
          
          # Test with mixed order (product + service) to ensure invoice is created
          order = create(:order,
            business: business_x,
            tenant_customer: tenant_customer_rewards,
            order_type: 'mixed',
            total_amount: product_variant_x.final_price + service_x.price,
            applied_promo_code: loyalty_code,
            promo_code_type: 'loyalty'
          )
          
          create(:line_item,
            lineable: order,
            product_variant: product_variant_x,
            quantity: 1,
            price: product_variant_x.final_price,
            total_amount: product_variant_x.final_price
          )
          
          create(:line_item,
            lineable: order,
            product_variant: nil,
            service: service_x,
            staff_member: staff_member_x,
            quantity: 1,
            price: service_x.price,
            total_amount: service_x.price
          )
          
          # Reload order to ensure invoice is created
          order.reload
          
          result = PromoCodeService.apply_code(loyalty_code, business_x, order, tenant_customer_rewards)
          expect(result[:success]).to be true
          
          # Test with business promotion stacking
          promotion = create(:promotion, :code_based, business: business_x, code: 'LOYALTY10', discount_type: 'percentage', discount_value: 10)
          promotion_result = PromotionManager.apply_promotion_to_invoice(order.invoice, 'LOYALTY10')
          expect(promotion_result[:valid]).to be true
          
          # Award loyalty points
          LoyaltyPointsService.award_order_points(order)
          
          points = LoyaltyTransaction.where(tenant_customer: tenant_customer_rewards, transaction_type: 'earned').sum(:points_amount)
          expect(points).to be > 0
        end
      end
    end
  end

  describe '4. Business User Platform Referrals (Standard and Premium)' do
    let!(:standard_business) { create(:business, tier: 'standard', name: 'Standard Business', hostname: 'standard') }
    let!(:premium_business) { create(:business, tier: 'premium', name: 'Premium Business', hostname: 'premium') }
    let!(:referred_business) { create(:business, tier: 'standard', name: 'Referred Business', hostname: 'referred') }
    
    before do
      # Mock Stripe API calls for platform referrals
      allow(Stripe::Coupon).to receive(:create).and_return(
        double('Stripe::Coupon', id: 'coupon_test_referral_123')
      )
    end

    describe 'Standard tier business referrals' do
      it 'generates platform referral code and earns points for successful referral' do
        # Generate platform referral code
        referral_code = PlatformLoyaltyService.generate_business_platform_referral_code(standard_business)
        expect(referral_code).to be_present
        
        # Process referral signup
        result = PlatformLoyaltyService.process_business_referral_signup(referred_business, referral_code)
        
        expect(result[:success]).to be true
        expect(result[:points_awarded]).to eq(500) # Standard referral reward
        
        # Check platform referral was created
        platform_referral = PlatformReferral.find_by(
          referrer_business: standard_business,
          referred_business: referred_business
        )
        
        expect(platform_referral).to be_present
        expect(platform_referral.status).to eq('rewarded')
        
        # Check platform loyalty points were awarded
        standard_business.reload
        expect(standard_business.platform_loyalty_points).to eq(500)
      end

      it 'allows standard business to redeem platform points for discounts' do
        # Give business some platform points
        standard_business.add_platform_loyalty_points!(500, 'Test points', nil)
        
        # Redeem points for discount
        redemption_result = PlatformLoyaltyService.create_discount_code(standard_business, 200)
        
        expect(redemption_result[:success]).to be true
        expect(redemption_result[:discount_code]).to be_present
        
        discount_code = redemption_result[:discount_code]
        expect(discount_code.points_redeemed).to eq(200)
        expect(discount_code.discount_amount).to eq(20.0) # $20 off
        
        # Check points were deducted
        standard_business.reload
        expect(standard_business.platform_loyalty_points).to eq(300) # 500 - 200
      end
    end

    describe 'Premium tier business referrals' do
      it 'generates referral code and earns enhanced rewards' do
        # Create a separate referred business for premium tier test
        premium_referred_business = create(:business, tier: 'standard', name: 'Premium Referred Business', hostname: 'premium-referred')
        
        referral_code = PlatformLoyaltyService.generate_business_platform_referral_code(premium_business)
        
        # Process referral
        result = PlatformLoyaltyService.process_business_referral_signup(premium_referred_business, referral_code)
        expect(result[:success]).to be true
        expect(result[:points_awarded]).to eq(500) # Same base reward, but premium features unlocked
        
        premium_business.reload
        expect(premium_business.platform_loyalty_points).to eq(500)
      end

      it 'allows premium business to redeem points for higher value discounts' do
        # Give premium business points
        premium_business.add_platform_loyalty_points!(1000, 'Premium test points', nil)
        
        # Redeem more points for bigger discount
        redemption_result = PlatformLoyaltyService.create_discount_code(premium_business, 500)
        
        expect(redemption_result[:success]).to be true
        
        discount_code = redemption_result[:discount_code]
        expect(discount_code.points_redeemed).to eq(500)
        expect(discount_code.discount_amount).to eq(50.0) # $50 off
        
        premium_business.reload
        expect(premium_business.platform_loyalty_points).to eq(500)
      end
    end

    describe 'Business referral validation scenarios' do
      it 'prevents business from referring themselves' do
        referral_code = PlatformLoyaltyService.generate_business_platform_referral_code(standard_business)
        
        result = PlatformLoyaltyService.process_business_referral_signup(standard_business, referral_code)
        
        expect(result[:success]).to be false
        expect(result[:error]).to include('cannot refer themselves')
      end

      it 'prevents duplicate referrals' do
        referral_code = PlatformLoyaltyService.generate_business_platform_referral_code(standard_business)
        
        # First referral succeeds
        first_result = PlatformLoyaltyService.process_business_referral_signup(referred_business, referral_code)
        expect(first_result[:success]).to be true
        
        # Second referral with same business fails
        second_result = PlatformLoyaltyService.process_business_referral_signup(referred_business, referral_code)
        expect(second_result[:success]).to be false
        expect(second_result[:error]).to include('already exists')
      end

      it 'validates referral code exists' do
        result = PlatformLoyaltyService.process_business_referral_signup(referred_business, 'INVALID-CODE')
        
        expect(result[:success]).to be false
        expect(result[:error]).to include('Invalid referral code')
      end
    end

    describe 'Platform discount code usage scenarios' do
      let!(:platform_discount) { create(:platform_discount_code, business: standard_business, points_redeemed: 300, discount_amount: 30.0) }

      it 'validates platform discount codes' do
        result = PlatformLoyaltyService.validate_platform_discount_code(platform_discount.code)
        
        expect(result[:valid]).to be true
        expect(result[:discount_code]).to eq(platform_discount)
        expect(result[:discount_code].can_be_used?).to be true
      end

      it 'marks platform discount codes as used after successful payment' do
        expect(platform_discount.status).to eq('active')
        
        PlatformLoyaltyService.mark_discount_code_used(platform_discount)
        
        platform_discount.reload
        expect(platform_discount.status).to eq('used')
      end

      it 'handles expired platform discount codes' do
        platform_discount.update!(expires_at: 1.day.ago)
        
        result = PlatformLoyaltyService.validate_platform_discount_code(platform_discount.code)
        
        expect(result[:valid]).to be false # Should not validate expired codes
        expect(result[:error]).to include('already been used')
      end
    end
  end

  describe 'Additional Edge Cases and Security Scenarios' do
    describe 'Cross-tenant security' do
      it 'prevents accessing other business loyalty data' do
        ActsAsTenant.with_tenant(business_x) do
          customer_x = create(:tenant_customer, business: business_x, email: 'security@test.com')
          create(:loyalty_transaction, tenant_customer: customer_x, business: business_x, points_amount: 100, transaction_type: 'earned')
        end
        
        ActsAsTenant.with_tenant(business_y) do
          # Should not see business X customer data
          customer_y_lookup = TenantCustomer.find_by(email: 'security@test.com')
          expect(customer_y_lookup).to be_nil
          
          # Should not see business X loyalty transactions
          transactions = LoyaltyTransaction.all
          expect(transactions.any? { |t| t.business_id == business_x.id }).to be false
        end
      end
    end

    describe 'Referral code security' do
      it 'generates unique referral codes per business' do
        # Create referrals within their respective tenant scopes
        referral_x = nil
        referral_y = nil
        
        ActsAsTenant.with_tenant(business_x) do
          tenant_customer_x = create(:tenant_customer, business: business_x, email: client_user_a.email)
          referral_x = create(:referral, business: business_x, referrer: client_user_a, referred_tenant_customer: tenant_customer_x)
        end
        
        ActsAsTenant.with_tenant(business_y) do
          tenant_customer_y = create(:tenant_customer, business: business_y, email: client_user_a.email)
          referral_y = create(:referral, business: business_y, referrer: client_user_a, referred_tenant_customer: tenant_customer_y)
        end
        
        expect(referral_x.referral_code).not_to eq(referral_y.referral_code)
        
        # Should be able to find each in their respective business scope
        expect(business_x.referrals.find_by(referral_code: referral_x.referral_code)).to eq(referral_x)
        expect(business_y.referrals.find_by(referral_code: referral_y.referral_code)).to eq(referral_y)
        
        # Should not find cross-business
        expect(business_x.referrals.find_by(referral_code: referral_y.referral_code)).to be_nil
        expect(business_y.referrals.find_by(referral_code: referral_x.referral_code)).to be_nil
      end
    end

    describe 'Loyalty program state changes' do
      it 'handles loyalty program being disabled mid-process' do
        customer = create(:tenant_customer, business: business_x, email: 'statechange@test.com')
        
        ActsAsTenant.with_tenant(business_x) do
          booking = create(:booking,
            business: business_x,
            tenant_customer: customer,
            service: service_x,
            staff_member: staff_member_x,
            amount: service_x.price
          )
          
          # Disable loyalty program
          business_x.update!(loyalty_program_enabled: false)
          
          # Should not award points when program is disabled
          expect {
            LoyaltyPointsService.award_booking_points(booking)
          }.not_to change { LoyaltyTransaction.count }
        end
      end
    end

    describe 'Point expiration scenarios' do
      it 'expires old loyalty points' do
        customer = create(:tenant_customer, business: business_x, email: 'expiration@test.com')
        
        ActsAsTenant.with_tenant(business_x) do
          # Create old transaction that should expire
          old_transaction = create(:loyalty_transaction,
            tenant_customer: customer,
            business: business_x,
            points_amount: 100,
            transaction_type: 'earned',
            description: 'Old points',
            expires_at: 1.day.ago
          )
          
          # Create recent transaction that should not expire
          recent_transaction = create(:loyalty_transaction,
            tenant_customer: customer,
            business: business_x,
            points_amount: 50,
            transaction_type: 'earned',
            description: 'Recent points',
            expires_at: 1.year.from_now
          )
          
          # Expire old points
          LoyaltyPointsService.expire_points
          
          old_transaction.reload
          recent_transaction.reload
          
          # Check that expired transaction was marked as expired
          expect(LoyaltyTransaction.exists?(
            tenant_customer: customer,
            transaction_type: 'expired',
            points_amount: -100
          )).to be true
          
          # Current balance should only include non-expired points
          balance = LoyaltyPointsService.calculate_customer_balance(customer)
          expect(balance).to eq(50)
        end
      end
    end
  end
end 