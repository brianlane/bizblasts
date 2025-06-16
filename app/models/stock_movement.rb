class StockMovement < ApplicationRecord
  belongs_to :product
  
  validates :product, :quantity, :movement_type, presence: true
  validates :quantity, numericality: { other_than: 0 }
  validates :movement_type, inclusion: { in: %w[subscription_fulfillment restock adjustment return] }
  
  scope :inbound, -> { where('quantity > 0') }
  scope :outbound, -> { where('quantity < 0') }
  scope :by_type, ->(type) { where(movement_type: type) }
  
  def inbound?
    quantity > 0
  end
  
  def outbound?
    quantity < 0
  end
end
