require 'rails_helper'

RSpec.describe 'Promotion and Discount Code Stacking', type: :service do
  let!(:business) { create(:business, hostname: 'testbiz') }
  let!(:customer) { create(:tenant_customer, business: business) }
  let!(:user) { create(:user, :client) }
  
  let!(:product) { create(:product, business: business, price: 100.00, name: 'Test Product') }
  let!(:product_variant) { create(:product_variant, product: product, price_modifier: 0.00) }
  let!(:service) { create(:service, business: business, price: 150.00, name: 'Test Service') }
  let!(:staff_member) { create(:staff_member, business: business) }
  
  # Create automatic promotion for products and services (allows stacking)
  let!(:promotion) do
    create(:promotion, :automatic, 
      business: business, 
      discount_type: 'percentage', 
      discount_value: 25,
      applicable_to_products: true,
      applicable_to_services: true
    )
  end
  
  # Create discount code
  let!(:discount_code) do
    create(:discount_code, 
      business: business, 
      code: 'EXTRA10', 
      discount_type: 'fixed_amount', 
      discount_value: 10.00
    )
  end
  
  before do
    ActsAsTenant.current_tenant = business
    
    # Associate promotion with specific products/services
    promotion.promotion_products.create!(product: product)
    promotion.promotion_services.create!(service: service)
  end

  describe 'Promotional pricing display behavior' do
    it 'automatically applies promotional pricing to products' do
      ActsAsTenant.with_tenant(business) do
        expect(product.on_promotion?).to be true
        expect(product.current_promotion).to eq(promotion)
        expect(product.promotional_price).to eq(75.00) # 100 - 25% = 75
        expect(product.promotion_discount_amount).to eq(25.00)
        expect(product.savings_percentage).to eq(25)
        expect(product.promotion_display_text).to eq('25% OFF')
      end
    end
    
    it 'automatically applies promotional pricing to services' do
      ActsAsTenant.with_tenant(business) do
        expect(service.on_promotion?).to be true
        expect(service.current_promotion).to eq(promotion)
        expect(service.promotional_price).to eq(112.50) # 150 - 25% = 112.50
        expect(service.promotion_discount_amount).to eq(37.50)
        expect(service.savings_percentage).to eq(25)
        expect(service.promotion_display_text).to eq('25% OFF')
      end
    end
  end

  describe 'Stacking promotional pricing with discount codes' do
    it 'allows discount codes to be applied on top of promotional pricing for products' do
      ActsAsTenant.with_tenant(business) do
        # Create order manually to avoid factory associations
        order = Order.new(
          business: business,
          tenant_customer: customer,
          tax_rate: nil,
          shipping_method: nil,
          status: 'pending_payment',
          order_type: 'product'
        )
        order.save!
        
        line_item = create(:line_item,
          lineable: order,
          product_variant: product_variant,
          quantity: 1,
          price: product.promotional_price, # Use promotional price
          total_amount: product.promotional_price
        )
        
        # Ensure order total is calculated before applying discount
        order.save!
        order.reload
        order.calculate_totals!
        order.save!
        order.reload
        
        # Apply discount code on top of promotional pricing
        result = PromoCodeService.apply_code('EXTRA10', business, order, customer)
        
        expect(result[:success]).to be true
        expect(result[:type]).to eq('discount')
        
                  order.reload
          # Final amount should be promotional price minus additional discount
          # Check that discount was applied
          expect(order.total_amount).to be < product.promotional_price
          expect(order.promo_discount_amount).to eq(10.00)
      end
    end
    
    it 'allows discount codes to be applied on top of promotional pricing for services' do
      ActsAsTenant.with_tenant(business) do
        # Create booking with promotional pricing (no discount code applied yet)
        booking = create(:booking,
          business: business,
          tenant_customer: customer,
          service: service,
          staff_member: staff_member,
          amount: service.promotional_price # Start with promotional price
        )
        
        # Apply discount code on top of promotional pricing
        result = PromoCodeService.apply_code('EXTRA10', business, booking, customer)
        
        expect(result[:success]).to be true
        expect(result[:type]).to eq('discount')
        
        booking.reload
        # Final amount should be promotional price minus additional discount
        # Check that discount was applied
        expect(booking.amount).to be < service.promotional_price
        expect(booking.promo_discount_amount).to eq(10.00)
      end
    end
    
          it 'handles mixed orders with both promotional pricing and discount codes' do
        ActsAsTenant.with_tenant(business) do
          order = create(:order,
            business: business,
            tenant_customer: customer,
            order_type: 'mixed',
            total_amount: product.promotional_price + service.promotional_price,
            applied_promo_code: 'EXTRA10',
            promo_code_type: 'discount'
          )
          
          # Add product line item with promotional pricing
          create(:line_item,
            lineable: order,
            product_variant: product_variant,
            quantity: 1,
            price: product.promotional_price,
            total_amount: product.promotional_price
          )
          
          # Add service line item with promotional pricing (without product_variant)
          create(:line_item,
            lineable: order,
            product_variant: nil,
            service: service,
            staff_member: staff_member,
            quantity: 1,
            price: service.promotional_price,
            total_amount: service.promotional_price
          )
          
          # Apply discount code
          result = PromoCodeService.apply_code('EXTRA10', business, order, customer)
          
          expect(result[:success]).to be true
          
          order.reload
          # Check that discount was applied
          expect(order.total_amount).to be < (product.promotional_price + service.promotional_price)
        end
      end
  end

  describe 'Promotional pricing with referral codes' do
    let!(:referral_program) do
      business.create_referral_program!(
        active: true,
        referrer_reward_type: 'points',
        referrer_reward_value: 100,
        referral_code_discount_amount: 10.0
      )
    end
    let!(:referral) { create(:referral, business: business, referrer: user, referred_tenant_customer: customer) }
    
    it 'combines promotional pricing with referral discounts' do
      ActsAsTenant.with_tenant(business) do
        # Enable referral program on business
        business.update!(referral_program_enabled: true)
        
        order = create(:order,
          business: business,
          tenant_customer: customer,
          total_amount: product.promotional_price,
          applied_promo_code: referral.referral_code,
          promo_code_type: 'referral'
        )
        
        create(:line_item,
          lineable: order,
          product_variant: product_variant,
          quantity: 1,
          price: product.promotional_price,
          total_amount: product.promotional_price
        )
        
        result = PromoCodeService.apply_code(referral.referral_code, business, order, customer)
        
        expect(result[:success]).to be true
        expect(result[:type]).to eq('referral')
        
        order.reload
        # Should get both promotional discount AND referral discount
        expect(order.total_amount).to be < product.promotional_price
      end
    end
  end

  describe 'Edge cases and validation' do
    it 'handles expired promotions correctly' do
      ActsAsTenant.with_tenant(business) do
        promotion.update!(end_date: 1.week.ago)
        
        expect(product.on_promotion?).to be false
        expect(product.promotional_price).to eq(100.00) # Back to original price
        expect(service.on_promotion?).to be false
        expect(service.promotional_price).to eq(150.00) # Back to original price
      end
    end
    
    it 'handles promotions with usage limits' do
      ActsAsTenant.with_tenant(business) do
        promotion.update!(usage_limit: 1, current_usage: 1)
        
        expect(product.on_promotion?).to be false
        expect(service.on_promotion?).to be false
      end
    end
    
    it 'handles inactive promotions' do
      # Update promotion to be inactive
      promotion.update!(active: false)
      
      expect(product.on_promotion?).to be false
      expect(service.on_promotion?).to be false
    end
    
    it 'allows replacing discount codes with newer ones - last code wins' do
      ActsAsTenant.with_tenant(business) do
        # Create a second discount code
        second_discount = create(:discount_code, 
          business: business, 
          code: 'EXTRA20', 
          discount_type: 'fixed_amount', 
          discount_value: 20.00,
          used_by_customer: nil,  # Not used by anyone yet
          single_use: false       # Allow multiple uses
        )
        
        # Create order with promotional pricing
        order = Order.new(
          business: business,
          tenant_customer: customer,
          tax_rate: nil,
          shipping_method: nil,
          status: 'pending_payment',
          order_type: 'product'
        )
        order.save!
        
        line_item = create(:line_item,
          lineable: order,
          product_variant: product_variant,
          quantity: 1,
          price: product.promotional_price, # $75 promotional price
          total_amount: product.promotional_price
        )
        
        order.save!
        order.reload
        order.calculate_totals!
        order.save!
        order.reload
        
        # Apply first discount code successfully
        result1 = PromoCodeService.apply_code('EXTRA10', business, order, customer)
        expect(result1[:success]).to be true
        expect(result1[:type]).to eq('discount')
        
        order.reload
        expect(order.applied_promo_code).to eq('EXTRA10')
        expect(order.promo_code_type).to eq('discount')
        original_total_after_first_discount = order.total_amount
        
        # Apply second discount code should succeed and replace the first one
        result2 = PromoCodeService.apply_code('EXTRA20', business, order, customer)
        expect(result2[:success]).to be true
        expect(result2[:type]).to eq('discount')
        
        # Order should now have the second discount code applied
        order.reload
        expect(order.applied_promo_code).to eq('EXTRA20') # Now second code
        expect(order.promo_code_type).to eq('discount')
        expect(order.promo_discount_amount).to eq(20.00) # New discount amount
        # Total should be less than the original total after first discount (since $20 > $10)
        expect(order.total_amount).to be < original_total_after_first_discount
      end
    end
    
    it 'allows replacing discount codes with newer ones for bookings - last code wins' do
      ActsAsTenant.with_tenant(business) do
        # Create a second discount code
        second_discount = create(:discount_code, 
          business: business, 
          code: 'SERVICE30', 
          discount_type: 'percentage', 
          discount_value: 30,
          used_by_customer: nil,  # Not used by anyone yet
          single_use: false       # Allow multiple uses
        )
        
        # Create booking with promotional pricing
        booking = create(:booking,
          business: business,
          tenant_customer: customer,
          service: service,
          staff_member: staff_member,
          amount: service.promotional_price # $120 promotional price
        )
        
        # Apply first discount code successfully
        result1 = PromoCodeService.apply_code('EXTRA10', business, booking, customer)
        expect(result1[:success]).to be true
        expect(result1[:type]).to eq('discount')
        
        booking.reload
        expect(booking.applied_promo_code).to eq('EXTRA10')
        expect(booking.promo_code_type).to eq('discount')
        original_amount_after_first_discount = booking.amount
        
        # Apply second discount code should succeed and replace the first one
        result2 = PromoCodeService.apply_code('SERVICE30', business, booking, customer)
        expect(result2[:success]).to be true
        expect(result2[:type]).to eq('discount')
        
        # Booking should now have the second discount code applied
        booking.reload
        expect(booking.applied_promo_code).to eq('SERVICE30') # Now second code
        expect(booking.promo_code_type).to eq('discount')
        # SERVICE30 is 30% off, so should be a bigger discount than EXTRA10 ($10 fixed)
        expect(booking.amount).to be < original_amount_after_first_discount
      end
    end
  end
end 