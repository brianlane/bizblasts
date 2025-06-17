require 'rails_helper'

RSpec.describe PromoCodeService, type: :service do
  let!(:business) { create(:business, hostname: 'testbiz') }
  let!(:customer) { create(:tenant_customer, business: business) }
  let!(:user) { create(:user, :client) }
  
  let!(:product) { create(:product, business: business, price: 100.00) }
  let!(:product_variant) { create(:product_variant, product: product, price_modifier: 0.00) }
  let!(:service) { create(:service, business: business, price: 150.00) }
  let!(:staff_member) { create(:staff_member, business: business) }
  
  before do
    ActsAsTenant.current_tenant = business
  end

  describe '.apply_code with promotional pricing' do
    let!(:promotion) do
      create(:promotion, :automatic,
        business: business,
        discount_type: 'percentage',
        discount_value: 20,
        applicable_to_products: true,
        applicable_to_services: true
      )
    end
    
    let!(:discount_code) do
      create(:discount_code,
        business: business,
        code: 'SAVE15',
        discount_type: 'fixed_amount',
        discount_value: 15.00
      )
    end
    
    before do
      promotion.promotion_products.create!(product: product)
      promotion.promotion_services.create!(service: service)
    end

    context 'applying discount code to order with promotional pricing' do
      it 'applies discount code on top of promotional pricing for products' do
        ActsAsTenant.with_tenant(business) do
          # Create discount code inside tenant context
          discount_code = create(:discount_code,
            business: business,
            code: 'SAVE15-TEST',
            discount_type: 'fixed_amount',
            discount_value: 15.00,
            used_by_customer: nil
          )
          # Verify promotional pricing is active
          expect(product.on_promotion?).to be true
          expect(product.promotional_price).to eq(80.00) # 100 - 20% = 80
          
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
            price: product.promotional_price,
            total_amount: product.promotional_price
          )
          
          # Ensure order total is calculated before applying discount
          order.save!
          order.reload
          order.calculate_totals!
          order.save!
          order.reload
          
          # Apply discount code
          result = PromoCodeService.apply_code('SAVE15-TEST', business, order, customer)
          
          expect(result[:success]).to be true
          expect(result[:type]).to eq('discount')
          expect(result[:discount_amount]).to eq(15.00)
          
          order.reload
          expect(order.total_amount).to eq(65.00) # 80 - 15 = 65
        end
      end
      
      it 'applies discount code on top of promotional pricing for services' do
        ActsAsTenant.with_tenant(business) do
          # Create discount code inside tenant context
          discount_code = create(:discount_code,
            business: business,
            code: 'SAVE15-SERVICE',
            discount_type: 'fixed_amount',
            discount_value: 15.00,
            used_by_customer: nil
          )
          
          # Verify promotional pricing is active
          expect(service.on_promotion?).to be true
          expect(service.promotional_price).to eq(120.00) # 150 - 20% = 120
          
          # Create booking using promotional pricing
          booking = create(:booking,
            business: business,
            tenant_customer: customer,
            service: service,
            staff_member: staff_member,
            amount: service.promotional_price
          )
          
          # Apply discount code
          result = PromoCodeService.apply_code('SAVE15-SERVICE', business, booking, customer)
          
          expect(result[:success]).to be true
          expect(result[:type]).to eq('discount')
          expect(result[:discount_amount]).to eq(15.00)
          
          booking.reload
          expect(booking.amount).to eq(105.00) # 120 - 15 = 105
        end
      end
    end

    context 'applying referral code to order with promotional pricing' do
      let!(:referral) { create(:referral, business: business, referrer: user, referred_tenant_customer: customer) }
      
      it 'applies referral discount on top of promotional pricing' do
        ActsAsTenant.with_tenant(business) do
          # Create referral program inside tenant context
          business.create_referral_program!(
            active: true,
            referrer_reward_type: 'points',
            referrer_reward_value: 50,
            referral_code_discount_amount: 10.0
          )
          # Enable referral program on business
          business.update!(referral_program_enabled: true)
          # Create order with promotional pricing
          order = create(:order,
            business: business,
            tenant_customer: customer,
            total_amount: product.promotional_price + service.promotional_price
          )
          
          create(:line_item,
            lineable: order,
            product_variant: product_variant,
            quantity: 1,
            price: product.promotional_price,
            total_amount: product.promotional_price
          )
          
          LineItem.create!(
            lineable: order,
            service: service,
            staff_member: staff_member,
            quantity: 1,
            price: service.promotional_price,
            total_amount: service.promotional_price
          )
          
          original_total = order.total_amount
          
          # Apply referral code
          result = PromoCodeService.apply_code(referral.referral_code, business, order, customer)
          
          expect(result[:success]).to be true
          expect(result[:type]).to eq('referral')
          
          order.reload
          expect(order.total_amount).to be < original_total
        end
      end
    end

    context 'validation with promotional pricing' do
      it 'validates discount codes correctly when items have promotional pricing' do
        ActsAsTenant.with_tenant(business) do
          # Create discount code inside tenant context
          discount_code = create(:discount_code,
            business: business,
            code: 'SAVE15-VALIDATION',
            discount_type: 'fixed_amount',
            discount_value: 15.00,
            used_by_customer: nil
          )
          
          validation = PromoCodeService.validate_code('SAVE15-VALIDATION', business, customer)
          
          expect(validation[:valid]).to be true
          expect(validation[:discount_code]).to eq(discount_code)
          expect(validation[:type]).to eq('discount')
        end
      end
      
      it 'handles invalid codes with promotional pricing' do
        ActsAsTenant.with_tenant(business) do
          validation = PromoCodeService.validate_code('INVALID', business, customer)
          
          expect(validation[:valid]).to be false
          expect(validation[:error]).to include('Invalid')
        end
      end
    end
  end

  describe 'loyalty code integration with promotional pricing' do
    let!(:loyalty_transaction) do
      create(:loyalty_transaction,
        tenant_customer: customer,
        business: business,
        points_amount: 100,
        transaction_type: 'earned'
      )
    end
    
    let!(:loyalty_code) do
      create(:discount_code,
        business: business,
        code: 'LOYALTY20',
        discount_type: 'fixed_amount',
        discount_value: 20.00,
        points_redeemed: 100,
        tenant_customer: customer
      )
    end

    it 'applies loyalty discount on promotional pricing' do
      ActsAsTenant.with_tenant(business) do
        # Create loyalty transaction and code inside tenant context
        loyalty_transaction = create(:loyalty_transaction,
          tenant_customer: customer,
          business: business,
          points_amount: 100,
          transaction_type: 'earned'
        )
        
        loyalty_code = create(:discount_code,
          business: business,
          code: 'LOYALTY20-TEST',
          discount_type: 'fixed_amount',
          discount_value: 20.00,
          points_redeemed: 100,
          tenant_customer: customer,
          used_by_customer: nil
        )
        
        # Create promotion
        promotion = create(:promotion,
          business: business,
          discount_type: 'percentage',
          discount_value: 15,
          applicable_to_products: true
        )
        promotion.promotion_products.create!(product: product)
        
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
          price: product.promotional_price,
          total_amount: product.promotional_price
        )
        
        # Ensure order total is calculated before applying discount
        order.save!
        order.reload
        order.calculate_totals!
        order.save!
        order.reload
        
        # Apply loyalty code
        result = PromoCodeService.apply_code('LOYALTY20-TEST', business, order, customer)
        
        expect(result[:success]).to be true
        expect(result[:type]).to eq('loyalty')
        
        order.reload
        expect(order.total_amount).to eq(65.00) # 85 - 20 = 65
      end
    end
  end

  describe '#apply_code' do
    context 'with products' do
      let!(:product_eligible) { create(:product, business: business, allow_discounts: true, price: 100) }
      let!(:product_ineligible) { create(:product, business: business, allow_discounts: false, price: 50) }
      let!(:variant_eligible) { create(:product_variant, product: product_eligible, price_modifier: 0) }
      let!(:variant_ineligible) { create(:product_variant, product: product_ineligible, price_modifier: 0) }
      
      let(:order) { create(:order, business: business, tenant_customer: customer) }
      let!(:line_item_eligible) { create(:line_item, order: order, product_variant: variant_eligible, quantity: 1, unit_price: 100) }
      let!(:line_item_ineligible) { create(:line_item, order: order, product_variant: variant_ineligible, quantity: 1, unit_price: 50) }
      
      context 'when order has eligible items' do
        it 'applies discount only to eligible items' do
          result = PromoCodeService.apply_code(discount_code.code, business, order, customer)
          
          expect(result[:success]).to be true
          expect(result[:discount_amount]).to eq(10) # 10% of $100
        end
      end
      
      context 'when order has no eligible items' do
        before do
          line_item_eligible.destroy
        end
        
        it 'rejects the discount code' do
          result = PromoCodeService.apply_code(discount_code.code, business, order, customer)
          
          expect(result[:success]).to be false
          expect(result[:error]).to include('None of the items in this order are eligible for discount codes')
        end
      end
    end
    
    context 'with services' do
      let!(:service_eligible) { create(:service, business: business, allow_discounts: true, price: 100) }
      let!(:service_ineligible) { create(:service, business: business, allow_discounts: false, price: 100) }
      
      context 'when booking service allows discounts' do
        let(:booking) { create(:booking, business: business, service: service_eligible, tenant_customer: customer, amount: 100) }
        
        it 'applies the discount' do
          result = PromoCodeService.apply_code(discount_code.code, business, booking, customer)
          
          expect(result[:success]).to be true
          expect(result[:discount_amount]).to eq(10) # 10% of $100
        end
      end
      
      context 'when booking service does not allow discounts' do
        let(:booking) { create(:booking, business: business, service: service_ineligible, tenant_customer: customer, amount: 100) }
        
        it 'rejects the discount code' do
          result = PromoCodeService.apply_code(discount_code.code, business, booking, customer)
          
          expect(result[:success]).to be false
          expect(result[:error]).to include('None of the items in this order are eligible for discount codes')
        end
      end
    end
  end
  
  describe '#transaction_has_discount_eligible_items?' do
    let(:service) { PromoCodeService.new }
    
    context 'with booking' do
      it 'returns true when service allows discounts' do
        service_model = create(:service, business: business, allow_discounts: true)
        booking = create(:booking, business: business, service: service_model)
        
        expect(service.send(:transaction_has_discount_eligible_items?, booking)).to be true
      end
      
      it 'returns false when service does not allow discounts' do
        service_model = create(:service, business: business, allow_discounts: false)
        booking = create(:booking, business: business, service: service_model)
        
        expect(service.send(:transaction_has_discount_eligible_items?, booking)).to be false
      end
    end
    
    context 'with order containing line items' do
      let!(:product_eligible) { create(:product, business: business, allow_discounts: true) }
      let!(:product_ineligible) { create(:product, business: business, allow_discounts: false) }
      let!(:variant_eligible) { create(:product_variant, product: product_eligible) }
      let!(:variant_ineligible) { create(:product_variant, product: product_ineligible) }
      
      it 'returns true when at least one item allows discounts' do
        order = create(:order, business: business)
        create(:line_item, order: order, product_variant: variant_eligible)
        create(:line_item, order: order, product_variant: variant_ineligible)
        
        expect(service.send(:transaction_has_discount_eligible_items?, order)).to be true
      end
      
      it 'returns false when no items allow discounts' do
        order = create(:order, business: business)
        create(:line_item, order: order, product_variant: variant_ineligible)
        
        expect(service.send(:transaction_has_discount_eligible_items?, order)).to be false
      end
    end
  end
  
  describe '#calculate_discount_eligible_amount' do
    let(:service) { PromoCodeService.new }
    
    context 'with booking' do
      it 'returns full amount when service allows discounts' do
        service_model = create(:service, business: business, allow_discounts: true)
        booking = create(:booking, business: business, service: service_model, amount: 100)
        
        expect(service.send(:calculate_discount_eligible_amount, booking)).to eq(100)
      end
      
      it 'returns zero when service does not allow discounts' do
        service_model = create(:service, business: business, allow_discounts: false)
        booking = create(:booking, business: business, service: service_model, amount: 100)
        
        expect(service.send(:calculate_discount_eligible_amount, booking)).to eq(0)
      end
    end
    
    context 'with order containing line items' do
      let!(:product_eligible) { create(:product, business: business, allow_discounts: true) }
      let!(:product_ineligible) { create(:product, business: business, allow_discounts: false) }
      let!(:variant_eligible) { create(:product_variant, product: product_eligible) }
      let!(:variant_ineligible) { create(:product_variant, product: product_ineligible) }
      
      it 'returns sum of only eligible line items' do
        order = create(:order, business: business)
        create(:line_item, order: order, product_variant: variant_eligible, quantity: 1, unit_price: 100, total_amount: 100)
        create(:line_item, order: order, product_variant: variant_ineligible, quantity: 1, unit_price: 50, total_amount: 50)
        
        expect(service.send(:calculate_discount_eligible_amount, order)).to eq(100)
      end
      
      it 'returns zero when no items are eligible' do
        order = create(:order, business: business)
        create(:line_item, order: order, product_variant: variant_ineligible, quantity: 1, unit_price: 50, total_amount: 50)
        
        expect(service.send(:calculate_discount_eligible_amount, order)).to eq(0)
      end
    end
  end
end 