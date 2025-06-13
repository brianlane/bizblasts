class PromotionService < ApplicationRecord
  belongs_to :promotion
  belongs_to :service
  
  validates :promotion_id, uniqueness: { scope: :service_id }
end
