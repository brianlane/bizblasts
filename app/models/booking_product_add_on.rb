class BookingProductAddOn < ApplicationRecord
  belongs_to :booking
  belongs_to :product_variant

  validates :booking, :product_variant, :quantity, :price, :total_amount, presence: true
  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
  validates :price, :total_amount, numericality: { greater_than_or_equal_to: 0 }

  before_validation :set_price_and_total, on: :create

  private

  def set_price_and_total
    self.price ||= product_variant.final_price if product_variant
    self.total_amount = (price.to_d * quantity.to_i).round(2) if price && quantity
  end
end 