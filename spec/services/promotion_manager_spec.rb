# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PromotionManager, type: :service do
  let!(:tenant) { create(:business) }
  let!(:customer) { create(:tenant_customer, business: tenant) }

  # Use around block for tenant context
  around do |example|
    ActsAsTenant.with_tenant(tenant) do
      example.run
    end
  end

  describe '.validate_promotion_code' do
    let!(:active_promo) { 
      create(:promotion, :percentage, business: tenant, code: 'VALID10') 
    }
    let!(:inactive_promo) { 
      create(:promotion, :inactive, business: tenant, code: 'INACTIVE') 
    }
    let!(:limited_promo) { 
      # Create promo with limit and usage equal to limit
      create(:promotion, :fixed_amount, business: tenant, code: 'LIMIT1', usage_limit: 1, current_usage: 1) 
    }
    let!(:single_use_promo) { 
      # Create promo with usage_limit = 1 to signify single use per customer
      create(:promotion, :single_use_by_limit, business: tenant, code: 'SINGLE')
    }
    let!(:redemption_for_single_use) { 
      # Customer already redeemed the single_use_promo
      create(:promotion_redemption, promotion: single_use_promo, tenant_customer: customer)
    }

    context 'with a valid, active code' do
      it 'returns valid: true and the promotion object' do
        result = described_class.validate_promotion_code('VALID10', tenant.id, customer.id)
        expect(result[:valid]).to be true
        expect(result[:promotion]).to eq(active_promo)
        expect(result[:error]).to be_nil
      end
    end

    context 'with an invalid code' do
      it 'returns valid: false and an error message' do
        result = described_class.validate_promotion_code('INVALIDCODE', tenant.id)
        expect(result[:valid]).to be false
        expect(result[:error]).to eq("Invalid promotion code")
        expect(result[:promotion]).to be_nil
      end
    end

    context 'with an inactive code (by date)' do
      let!(:inactive_by_date) { create(:promotion, business: tenant, code: 'DATEINACTIVE', active: true, start_date: 2.months.ago, end_date: 1.month.ago) }
      it 'returns valid: false and an error message' do
        result = described_class.validate_promotion_code('DATEINACTIVE', tenant.id)
        expect(result[:valid]).to be false
        expect(result[:error]).to eq("Promotion has expired or not yet active")
      end
    end
    
    context 'with an inactive code (by flag)' do
      let!(:inactive_by_flag) { create(:promotion, :inactive, business: tenant, code: 'FLAGINACTIVE', start_date: 1.week.ago, end_date: 1.month.from_now) }
      it 'returns valid: false and an error message' do
        result = described_class.validate_promotion_code('FLAGINACTIVE', tenant.id)
        expect(result[:valid]).to be false
        expect(result[:error]).to eq("Promotion has expired or not yet active")
      end
    end

    context 'with a code that reached its usage limit' do
      it 'returns valid: false and an error message' do
        # Setup ensures current_usage >= usage_limit
        expect(limited_promo.usage_limit_reached?).to be true
        expect(limited_promo.single_use?).to be true # As limit is 1
        result = described_class.validate_promotion_code('LIMIT1', tenant.id)
        expect(result[:valid]).to be false
        expect(result[:error]).to eq("This promotion has reached its maximum number of uses") 
      end
    end

    context 'with a single-use code (limit=1) already redeemed by the customer' do
       it 'returns valid: false and an error message' do
         expect(single_use_promo.single_use?).to be true
         # Corrected exists? check
         expect(PromotionRedemption.exists?(promotion: single_use_promo, tenant_customer_id: customer.id)).to be true
         
         # Pass customer.id (tenant_customer_id)
         result = described_class.validate_promotion_code('SINGLE', tenant.id, customer.id)
         
         expect(result[:valid]).to be false
         expect(result[:error]).to eq("You have already used this promotion") 
       end
     end

    context 'with a single-use code (limit=1) not yet redeemed by the customer' do
      # Create customer correctly using tenant factory
      let!(:other_customer) { create(:tenant_customer, business: tenant) }
      it 'returns valid: true' do
        expect(single_use_promo.single_use?).to be true
        # Pass other_customer.id
        result = described_class.validate_promotion_code('SINGLE', tenant.id, other_customer.id)
        expect(result[:valid]).to be true
        expect(result[:promotion]).to eq(single_use_promo)
      end
    end
    
    # TODO: Add tests for model having explicit single_use boolean if needed
  end
  
  describe '.apply_promotion_to_booking' do
    let!(:service) { create(:service, business: tenant, price: 100.00) }
    let!(:staff_member) { create(:staff_member, business: tenant) }
    let!(:booking) { 
      create(:booking, business: tenant, tenant_customer: customer, service: service, staff_member: staff_member, amount: service.price)
    }
    let!(:percent_promo) { 
      create(:promotion, :percentage, business: tenant, code: 'PERCENT20', discount_value: 20)
    }
    let!(:fixed_promo) { 
      create(:promotion, :fixed_amount, business: tenant, code: 'FIXED10', discount_value: 10)
    }
    let!(:limited_promo_apply) { 
      create(:promotion, :percentage, business: tenant, code: 'LIMITAPPLY', discount_value: 5, usage_limit: 1, current_usage: 0)
    }

    context 'with a valid percentage promotion' do
      it 'applies the discount, updates the booking, increments usage, and creates redemption' do
        expect { 
          result = described_class.apply_promotion_to_booking(booking, 'PERCENT20')
          
          expect(result[:valid]).to be true
          expect(result[:promotion]).to eq(percent_promo)
          expect(result[:original_amount]).to eq(100.00)
          expect(result[:discount_amount]).to eq(20.00) # 20% of 100
          expect(result[:final_amount]).to eq(80.00)
          
          booking.reload
          expect(booking.promotion_id).to eq(percent_promo.id)
          expect(booking.discount_amount).to eq(20.00)
          expect(booking.amount).to eq(80.00)
          
          percent_promo.reload
          expect(percent_promo.current_usage).to eq(1)
        }.to change(PromotionRedemption, :count).by(1)
        
        redemption = PromotionRedemption.last
        expect(redemption.promotion).to eq(percent_promo)
        expect(redemption.tenant_customer).to eq(customer)
        expect(redemption.booking).to eq(booking)
      end
    end

    context 'with a valid fixed amount promotion' do
      it 'applies the discount, updates the booking, increments usage, and creates redemption' do
         expect { 
           result = described_class.apply_promotion_to_booking(booking, 'FIXED10')
           
           expect(result[:valid]).to be true
           expect(result[:promotion]).to eq(fixed_promo)
           expect(result[:original_amount]).to eq(100.00)
           expect(result[:discount_amount]).to eq(10.00) # Fixed $10
           expect(result[:final_amount]).to eq(90.00)

           booking.reload
           expect(booking.promotion_id).to eq(fixed_promo.id)
           expect(booking.discount_amount).to eq(10.00)
           expect(booking.amount).to eq(90.00)
           
           fixed_promo.reload
           expect(fixed_promo.current_usage).to eq(1)
         }.to change(PromotionRedemption, :count).by(1)
         
         redemption = PromotionRedemption.last
         expect(redemption.promotion).to eq(fixed_promo)
         expect(redemption.tenant_customer).to eq(customer)
         expect(redemption.booking).to eq(booking)
       end
    end

    context 'with an invalid promotion code' do
      it 'returns the validation error and does not change booking or redemptions' do
        expect { 
          result = described_class.apply_promotion_to_booking(booking, 'INVALIDCODE')
          expect(result[:valid]).to be false
          expect(result[:error]).to eq("Invalid promotion code")
          
          booking.reload
          expect(booking.promotion_id).to be_nil
          expect(booking.discount_amount).to be_nil
          expect(booking.amount).to eq(100.00)
        }.not_to change(PromotionRedemption, :count)
      end
    end
    
    context 'when usage limit is reached between validation and application' do
      it 'returns an error and does not apply the promotion' do
        # Simulate limit being reached after validation but before update
        allow(Promotion).to receive(:find_by).and_return(limited_promo_apply)
        allow(limited_promo_apply).to receive(:usage_limit_reached?).and_return(false, true) # False for validate, True for apply check
        
        expect {
          result = described_class.apply_promotion_to_booking(booking, 'LIMITAPPLY')
          expect(result[:valid]).to be false
          expect(result[:error]).to eq("Promotion usage limit reached just before applying.")

          booking.reload
          expect(booking.promotion_id).to be_nil
          expect(limited_promo_apply.current_usage).to eq(0) # Usage not incremented
        }.not_to change(PromotionRedemption, :count)
      end
    end
    
    context 'when fixed discount is greater than booking amount' do
      let!(:expensive_fixed_promo) { create(:promotion, :fixed_amount, business: tenant, code: 'OVER150', discount_value: 150.00) }
      it 'discounts amount to 0 and records correct discount amount' do
        expect { 
          result = described_class.apply_promotion_to_booking(booking, 'OVER150')
          
          expect(result[:valid]).to be true
          expect(result[:promotion]).to eq(expensive_fixed_promo)
          expect(result[:original_amount]).to eq(100.00)
          expect(result[:discount_amount]).to eq(100.00) # Capped at original amount
          expect(result[:final_amount]).to eq(0.00)

          booking.reload
          expect(booking.promotion_id).to eq(expensive_fixed_promo.id)
          expect(booking.discount_amount).to eq(100.00)
          expect(booking.amount).to eq(0.00)
          
          expensive_fixed_promo.reload
          expect(expensive_fixed_promo.current_usage).to eq(1)
        }.to change(PromotionRedemption, :count).by(1)
      end
    end

    context 'when booking amount is already 0' do
      before do
        # Modify the existing booking for this context
        booking.update!(amount: 0.00, original_amount: 0.00, discount_amount: nil, promotion: nil) 
        # Also reload the percent_promo to reset usage count from previous tests in the group
        percent_promo.reload 
      end
      
      it 'does not apply further discount but records redemption and increments usage' do
        initial_usage = percent_promo.current_usage
        
        expect { 
          # Use the modified booking
          result = described_class.apply_promotion_to_booking(booking, 'PERCENT20')
          
          expect(result[:valid]).to be true
          expect(result[:promotion]).to eq(percent_promo)
          expect(result[:original_amount]).to eq(0.00)
          expect(result[:discount_amount]).to eq(0.00) # No discount applied
          expect(result[:final_amount]).to eq(0.00)

          booking.reload
          expect(booking.promotion_id).to eq(percent_promo.id)
          expect(booking.discount_amount).to eq(0.00)
          expect(booking.amount).to eq(0.00)
          
          percent_promo.reload
          expect(percent_promo.current_usage).to eq(initial_usage + 1)

        }.to change(PromotionRedemption, :count).by(1)
      end
    end
    
    # TODO: Remove handled TODOs
  end
  
  describe '.apply_promotion_to_invoice' do
    let!(:service) { create(:service, business: tenant, price: 100.00) }
    let!(:staff_member) { create(:staff_member, business: tenant) }
    # Booking needed for invoice context
    let!(:booking_for_invoice) { 
      create(:booking, business: tenant, tenant_customer: customer, service: service, staff_member: staff_member, amount: service.price)
    }
    let!(:invoice) { 
      create(:invoice, business: tenant, tenant_customer: customer, booking: booking_for_invoice, amount: booking_for_invoice.amount, total_amount: booking_for_invoice.amount)
    }
    let!(:percent_promo_inv) { 
      create(:promotion, :percentage, business: tenant, code: 'INVPERCENT15', discount_value: 15)
    }
    let!(:fixed_promo_inv) { 
      create(:promotion, :fixed_amount, business: tenant, code: 'INVFIXED25', discount_value: 25)
    }

    # Basic success case - more detailed checks similar to booking apply
    context 'with a valid percentage promotion' do
      it 'applies discount, updates invoice, increments usage, creates redemption' do
        initial_usage = percent_promo_inv.current_usage
        expect { 
          result = described_class.apply_promotion_to_invoice(invoice, 'INVPERCENT15')
          
          expect(result[:valid]).to be true
          expect(result[:promotion]).to eq(percent_promo_inv)
          expect(result[:original_amount]).to eq(100.00)
          expect(result[:discount_amount]).to eq(15.00) # 15% of 100
          expect(result[:final_amount]).to eq(85.00)
          
          invoice.reload
          expect(invoice.promotion_id).to eq(percent_promo_inv.id)
          # Assuming invoice model also has discount_amount and original_amount? Need to check.
          # Let's assume it does for now based on service code.
          expect(invoice.discount_amount).to eq(15.00)
          expect(invoice.amount).to eq(85.00) # Check if service updates amount or total_amount
          
          percent_promo_inv.reload
          expect(percent_promo_inv.current_usage).to eq(initial_usage + 1)
        }.to change(PromotionRedemption, :count).by(1)
        
        redemption = PromotionRedemption.last
        expect(redemption.promotion).to eq(percent_promo_inv)
        expect(redemption.tenant_customer).to eq(customer)
        expect(redemption.booking).to eq(booking_for_invoice) # Check booking linked via invoice
      end
    end

    context 'with an invalid promotion code' do
      it 'returns validation error and does not modify invoice or redemption' do
        expect { 
          result = described_class.apply_promotion_to_invoice(invoice, 'INVALIDCODE')
          expect(result[:valid]).to be false
          expect(result[:error]).to eq("Invalid promotion code")
          
          invoice.reload
          expect(invoice.promotion_id).to be_nil
        }.not_to change(PromotionRedemption, :count)
      end
    end
    
    # TODO: Add other cases (fixed, limits, edge cases) similar to booking tests
  end
  
  describe '.generate_unique_code' do
    it 'generates a code with default prefix and length' do
      code = described_class.generate_unique_code
      expect(code).to match(/^[A-Z]{2}\d{4}$/)
    end

    it 'generates a code with a custom prefix' do
      prefix = 'TEST'
      code = described_class.generate_unique_code(prefix)
      expect(code).to start_with(prefix)
      expect(code).to match(/^#{prefix}\d{4}$/)
    end

    it 'generates unique codes' do
      codes = Set.new
      10.times { codes.add(described_class.generate_unique_code) }
      expect(codes.size).to eq(10)
    end

    # Note: Testing the loop for *guaranteed* uniqueness against existing DB codes 
    # is tricky without potentially polluting the DB or complex stubbing.
    # This basic test covers the generation logic.
  end
end 