class PromotionManager
  # This service handles promotion-related operations including
  # code validation, redemption, and application to bookings/invoices

  def self.validate_promotion_code(code, business_id, customer_id = nil)
    promotion = Promotion.find_by(code: code, business_id: business_id)
    
    return { valid: false, error: "Invalid promotion code" } unless promotion
    
    # Check if promotion is active (using the boolean column and dates)
    unless promotion.active && promotion.start_date <= Time.current && promotion.end_date >= Time.current
      return { valid: false, error: "Promotion has expired or not yet active" }
    end
    
    # Check if customer has already redeemed (if single-use and customer provided)
    if customer_id.present? && promotion.single_use? # Uses method from model
      # Corrected check: remove business_id from scope
      if PromotionRedemption.exists?(promotion: promotion, tenant_customer_id: customer_id)
        return { valid: false, error: "You have already used this promotion" }
      end
    end
    
    # Check if promotion has reached max redemptions (using the columns)
    if promotion.usage_limit_reached? # Uses method from model
      return { valid: false, error: "This promotion has reached its maximum number of uses" }
    end
    
    { valid: true, promotion: promotion }
  end
  
  def self.apply_promotion_to_booking(booking, promotion_code)
    result = validate_promotion_code(promotion_code, booking.business_id, booking.tenant_customer_id)
    
    return result unless result[:valid]
    
    promotion = result[:promotion]
    
    # Check usage limit again before applying (race condition mitigation)
    if promotion.usage_limit_reached?
      return { valid: false, error: "Promotion usage limit reached just before applying." }
    end
    
    # Calculate the discount
    original_amount = booking.amount || 0
    discount_amount = calculate_discount(original_amount, promotion)
    
    # Apply the discount to the booking
    discounted_amount = [original_amount - discount_amount, 0].max
    
    # Update booking and redemption in a transaction
    ApplicationRecord.transaction do
      booking.update!(
        promotion_id: promotion.id,
        original_amount: original_amount,
        discount_amount: discount_amount,
        amount: discounted_amount
      )
      
      # Record the redemption & increment usage count
      create_redemption(promotion, booking.tenant_customer, booking)
    end
    
    { 
      valid: true, 
      promotion: promotion, 
      original_amount: original_amount,
      discount_amount: discount_amount,
      final_amount: discounted_amount
    }
  rescue ActiveRecord::RecordInvalid => e
    # Handle potential validation errors (e.g., redemption uniqueness)
    { valid: false, error: e.message }
  end
  
  def self.apply_promotion_to_invoice(invoice, promotion_code)
    result = validate_promotion_code(promotion_code, invoice.business_id, invoice.tenant_customer_id)
    
    return result unless result[:valid]
    
    promotion = result[:promotion]
    
    # Check usage limit again before applying
    if promotion.usage_limit_reached?
      return { valid: false, error: "Promotion usage limit reached just before applying." }
    end
    
    # Calculate the discount
    original_amount = invoice.amount || 0
    discount_amount = calculate_discount(original_amount, promotion)
    
    # Apply the discount to the invoice
    discounted_amount = [original_amount - discount_amount, 0].max
    
    # Update invoice and redemption in a transaction
    ApplicationRecord.transaction do
      invoice.update!(
        promotion_id: promotion.id,
        original_amount: original_amount,
        discount_amount: discount_amount,
        amount: discounted_amount
      )
      
      # Record the redemption & increment usage count
      booking = invoice.respond_to?(:booking) ? invoice.booking : nil
      create_redemption(promotion, invoice.tenant_customer, booking)
    end
    
    { 
      valid: true, 
      promotion: promotion, 
      original_amount: original_amount,
      discount_amount: discount_amount,
      final_amount: discounted_amount
    }
  rescue ActiveRecord::RecordInvalid => e
    { valid: false, error: e.message }
  end
  
  def self.generate_unique_code(prefix = nil)
    prefix ||= ('A'..'Z').to_a.sample(2).join
    
    loop do
      code = "#{prefix}#{rand(1000..9999)}"
      return code unless Promotion.exists?(code: code)
    end
  end
  
  private
  
  def self.calculate_discount(amount, promotion)
    if promotion.percentage?
      (amount * (promotion.discount_value / 100.0)).round(2)
    elsif promotion.fixed_amount?
      [promotion.discount_value, amount].min
    else
      0
    end
  end
  
  def self.create_redemption(promotion, customer, booking = nil)
    # Create redemption and increment usage count atomically
    redemption = PromotionRedemption.create!(
      promotion: promotion,
      tenant_customer: customer, # Use correct association
      booking: booking,
      redeemed_at: Time.current
    )
    promotion.increment!(:current_usage)
    redemption
  end
end
