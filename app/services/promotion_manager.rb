class PromotionManager
  # This service handles promotion-related operations including
  # code validation, redemption, and application to bookings/invoices

  def self.validate_promotion_code(code, business_id, customer_id = nil)
    promotion = Promotion.find_by(code: code, business_id: business_id)
    
    return { valid: false, error: "Invalid promotion code" } unless promotion
    
    # Check if promotion is active
    unless promotion.active?
      return { valid: false, error: "Promotion has expired or not yet active" }
    end
    
    # Check if customer has already redeemed (if single-use and customer provided)
    if customer_id.present? && promotion.single_use?
      if PromotionRedemption.exists?(promotion: promotion, customer_id: customer_id, business_id: business_id)
        return { valid: false, error: "You have already used this promotion" }
      end
    end
    
    # Check if promotion has reached max redemptions
    if promotion.max_redemptions.present? && promotion.max_redemptions > 0
      if promotion.redeemed_count >= promotion.max_redemptions
        return { valid: false, error: "This promotion has reached its maximum number of uses" }
      end
    end
    
    { valid: true, promotion: promotion }
  end
  
  def self.apply_promotion_to_booking(booking, promotion_code)
    result = validate_promotion_code(promotion_code, booking.business_id, booking.customer_id)
    
    return result unless result[:valid]
    
    promotion = result[:promotion]
    
    # Calculate the discount
    original_amount = booking.amount || 0
    discount_amount = calculate_discount(original_amount, promotion)
    
    # Apply the discount to the booking
    discounted_amount = [original_amount - discount_amount, 0].max
    
    booking.update(
      promotion_id: promotion.id,
      original_amount: original_amount,
      discount_amount: discount_amount,
      amount: discounted_amount
    )
    
    # Record the redemption
    create_redemption(promotion, booking.customer, booking)
    
    { 
      valid: true, 
      promotion: promotion, 
      original_amount: original_amount,
      discount_amount: discount_amount,
      final_amount: discounted_amount
    }
  end
  
  def self.apply_promotion_to_invoice(invoice, promotion_code)
    result = validate_promotion_code(promotion_code, invoice.business_id, invoice.customer_id)
    
    return result unless result[:valid]
    
    promotion = result[:promotion]
    
    # Calculate the discount
    original_amount = invoice.amount || 0
    discount_amount = calculate_discount(original_amount, promotion)
    
    # Apply the discount to the invoice
    discounted_amount = [original_amount - discount_amount, 0].max
    
    invoice.update(
      promotion_id: promotion.id,
      original_amount: original_amount,
      discount_amount: discount_amount,
      amount: discounted_amount
    )
    
    # Record the redemption
    create_redemption(promotion, invoice.customer, invoice.booking)
    
    { 
      valid: true, 
      promotion: promotion, 
      original_amount: original_amount,
      discount_amount: discount_amount,
      final_amount: discounted_amount
    }
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
    PromotionRedemption.create(
      promotion: promotion,
      customer: customer,
      booking: booking,
      business_id: promotion.business_id,
      redeemed_at: Time.current
    )
  end
end
