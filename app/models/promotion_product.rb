class PromotionProduct < ApplicationRecord
  belongs_to :promotion
  belongs_to :product
  
  validates :promotion_id, uniqueness: { scope: :product_id }
end
