class PromoCodeService
  class << self
    def validate_code(code, business, customer = nil)
      return { valid: false, error: 'Code required' } unless code.present?
      
      # 1. Check Promotion codes
      promotion_result = validate_promotion_code(code, business, customer)
      return promotion_result if promotion_result[:valid]
      
      # 2. Check Referral codes
      referral_result = ReferralService.validate_referral_code(code, business, customer)
      return referral_result if referral_result[:valid]
      
      # 3. Check general Discount codes
      discount_result = validate_discount_code(code, business, customer)
      return discount_result if discount_result[:valid]
      
      { valid: false, error: 'Invalid or expired promo code' }
    end
    
    def apply_code(code, business, transaction_record, customer = nil)
      # Check if the same code is already applied AND the discount has been processed (idempotent)
      if transaction_record.applied_promo_code.present? && 
         transaction_record.applied_promo_code == code &&
         transaction_record.promo_discount_amount.present?
        return { success: true, message: 'Code already applied', type: transaction_record.promo_code_type }
      end
      
      # Validate the new code
      validation = validate_code(code, business, customer)
      return { success: false, error: validation[:error] } unless validation[:valid]
      
      # If a different code was previously applied, we'll replace it with the new one
      # This allows customers to try different codes and the last one wins
      
      # Revert any previous discount if one was applied
      if transaction_record.applied_promo_code.present?
        revert_previous_discount(transaction_record)
      end
      
      # Apply the new code
      case validation[:type]
      when 'promotion'
        apply_promotion_code(validation[:promotion], transaction_record, customer)
      when 'referral'
        apply_referral_code(validation[:referral], transaction_record, customer)
      when 'loyalty', 'discount'
        apply_discount_code(validation[:discount_code], transaction_record, customer)
      else
        { success: false, error: 'Unknown code type' }
      end
    end
    
    def calculate_discount(code, business, amount, customer = nil)
      validation = validate_code(code, business, customer)
      return 0 unless validation[:valid]
      
      case validation[:type]
      when 'promotion'
        validation[:promotion].calculate_discount(amount)
      when 'referral'
        # Referral codes are discount codes generated from referrals
        business.referral_program&.referral_code_discount_amount || 0
      when 'loyalty', 'discount'
        validation[:discount_code].calculate_discount(amount)
      else
        0
      end
    end
    
    private
    
    def revert_previous_discount(transaction_record)
      # Restore original amount if it was stored
      if transaction_record.respond_to?(:original_amount) && transaction_record.original_amount.present?
        if transaction_record.is_a?(Booking)
          transaction_record.update!(amount: transaction_record.original_amount)
        else
          # For orders, restore the total_amount by adding back the discount
          if transaction_record.promo_discount_amount.present?
            original_total = transaction_record.total_amount + transaction_record.promo_discount_amount
            transaction_record.update!(total_amount: original_total)
          end
        end
      else
        # If original amount wasn't stored, add back the discount amount
        if transaction_record.promo_discount_amount.present?
          if transaction_record.is_a?(Booking)
            current_amount = transaction_record.amount || 0
            restored_amount = current_amount + transaction_record.promo_discount_amount
            transaction_record.update!(amount: restored_amount)
          else
            current_total = transaction_record.total_amount || 0
            restored_total = current_total + transaction_record.promo_discount_amount
            transaction_record.update!(total_amount: restored_total)
          end
        end
      end
      
      # Clear the previous promo code fields
      transaction_record.update!(
        applied_promo_code: nil,
        promo_discount_amount: nil,
        promo_code_type: nil
      )
    end
    
    def validate_promotion_code(code, business, customer)
      promotion = business.promotions.find_by(code: code)
      return { valid: false, error: 'Promotion not found' } unless promotion
      
      # Use existing PromotionManager validation
      result = PromotionManager.validate_promotion_code(code, business.id, customer&.id)
      
      if result[:valid]
        { 
          valid: true, 
          type: 'promotion', 
          promotion: result[:promotion],
          discount_amount: result[:promotion].calculate_discount(100) # Sample calculation
        }
      else
        { valid: false, error: result[:error] }
      end
    end
    
    # This method is now a simple pass-through to the more robust validation in ReferralService
    def validate_referral_code(code, business, customer)
      ReferralService.validate_referral_code(code, business, customer)
    end
    
    def validate_discount_code(code, business, customer)
      discount_code = business.discount_codes.find_by(code: code)
      return { valid: false, error: 'Discount code not found' } unless discount_code
      
      return { valid: false, error: 'Code expired or inactive' } unless discount_code.valid_for_use?
      
      return { valid: false, error: 'Code cannot be used by this customer' } unless discount_code.can_be_used_by?(customer)
      
      # Determine if this is a loyalty-redeemed discount code
      type = discount_code.points_redeemed > 0 ? 'loyalty' : 'discount'
      
      { 
        valid: true, 
        type: type, 
        discount_code: discount_code,
        discount_amount: discount_code.calculate_discount(100) # Sample calculation
      }
    end
    
    def apply_promotion_code(promotion, transaction_record, customer)
      discount_amount = promotion.calculate_discount(transaction_record.total_amount || transaction_record.amount)
      
      # Update transaction record
      transaction_record.update!(
        applied_promo_code: promotion.code,
        promo_discount_amount: discount_amount,
        promo_code_type: 'promotion'
      )
      
      # Create promotion redemption
      PromotionRedemption.create!(
        promotion: promotion,
        tenant_customer: customer,
        booking: transaction_record.is_a?(Booking) ? transaction_record : nil,
        invoice: transaction_record.is_a?(Invoice) ? transaction_record : nil
      )
      
      # Update promotion usage
      promotion.increment!(:current_usage)
      
      { success: true, discount_amount: discount_amount, type: 'promotion' }
    end
    
    def apply_referral_code(referral, transaction_record, customer)
      business = referral.business
      referral_program = business.referral_program
      
      # The discount is applied to the new customer's transaction
      discount_amount = referral_program.referral_code_discount_amount
      
      transaction_record.update!(
        applied_promo_code: referral.referral_code,
        promo_discount_amount: discount_amount,
        promo_code_type: 'referral'
      )
      
      # Process the referral to give the referrer their reward
      ReferralService.process_referral_checkout(referral, transaction_record, customer)
      
      { success: true, discount_amount: discount_amount, type: 'referral' }
    end
    
    def apply_discount_code(discount_code, transaction_record, customer)
      # Check if any items in the transaction are eligible for discounts
      unless transaction_has_discount_eligible_items?(transaction_record)
        return { success: false, error: 'None of the items in this order are eligible for discount codes' }
      end
      
      # Get the discount-eligible amount from the transaction record
      eligible_amount = calculate_discount_eligible_amount(transaction_record)
      return { success: false, error: 'No eligible items for discount' } if eligible_amount <= 0
      
      discount_amount = discount_code.calculate_discount(eligible_amount)
      
      # Determine if this is a loyalty code or regular discount code
      code_type = discount_code.points_redeemed > 0 ? 'loyalty' : 'discount'
      
      # Update transaction record
      update_attrs = {
        applied_promo_code: discount_code.code,
        promo_discount_amount: discount_amount,
        promo_code_type: code_type
      }
      
              # For bookings, also update the amount to reflect the discount
        if transaction_record.is_a?(Booking)
          # Store original amount if not already set
          update_attrs[:original_amount] = eligible_amount if transaction_record.original_amount.nil?
          # Calculate final amount after discount
          update_attrs[:amount] = [eligible_amount - discount_amount, 0].max
        end
      
      transaction_record.update!(update_attrs)
      
      # Mark discount code as used
      discount_code.mark_used!(customer)
      
      { success: true, discount_amount: discount_amount, type: code_type }
    end
    
    # Check if transaction has any items eligible for discounts
    def transaction_has_discount_eligible_items?(transaction_record)
      if transaction_record.is_a?(Booking)
        # For bookings, check if the service allows discounts
        return false unless transaction_record.service&.discount_eligible?
        true
      elsif transaction_record.respond_to?(:line_items)
        # For orders with line items, check if any item allows discounts
        transaction_record.line_items.any? do |line_item|
          if line_item.product?
            line_item.product_variant&.product&.discount_eligible?
          elsif line_item.service?
            line_item.service&.discount_eligible?
          else
            false
          end
        end
      else
        # Default to true for other transaction types
        true
      end
    end
    
    # Calculate the total amount eligible for discounts
    def calculate_discount_eligible_amount(transaction_record)
      if transaction_record.is_a?(Booking)
        # For bookings, return full amount if service allows discounts
        return 0 unless transaction_record.service&.discount_eligible?
        transaction_record.amount || 0
      elsif transaction_record.respond_to?(:line_items)
        # For orders, sum only eligible line items
        eligible_amount = 0
        
        transaction_record.line_items.each do |line_item|
          is_eligible = if line_item.product?
            line_item.product_variant&.product&.discount_eligible?
          elsif line_item.service?
            line_item.service&.discount_eligible?
          else
            false
          end
          
          eligible_amount += line_item.total_amount if is_eligible
        end
        
        eligible_amount
      else
        # For other transaction types, return full amount
        transaction_record.respond_to?(:total_amount) ? transaction_record.total_amount : transaction_record.amount
      end
    end
  end
end 