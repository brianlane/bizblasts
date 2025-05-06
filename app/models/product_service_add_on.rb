class ProductServiceAddOn < ApplicationRecord
  belongs_to :product
  belongs_to :service

  validates :product_id, presence: true
  validates :service_id, presence: true
end 