class PromotionRedemption < ApplicationRecord
  belongs_to :promotion
  belongs_to :tenant_customer, class_name: 'TenantCustomer'
  belongs_to :booking, optional: true
  
  validates :tenant_customer_id, uniqueness: { scope: :promotion_id, 
                                      message: "has already redeemed this promotion" }, 
                        if: -> { promotion&.single_use? }
  
  scope :for_promotion, ->(promotion_id) { where(promotion_id: promotion_id) }
  
  def discount_amount(subtotal)
    return 0 unless promotion
    
    if promotion.percentage?
      (subtotal * (promotion.discount_value / 100.0)).round(2)
    elsif promotion.fixed_amount?
      [promotion.discount_value, subtotal].min
    else
      0
    end
  end
end 