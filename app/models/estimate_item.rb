class EstimateItem < ApplicationRecord
  belongs_to :estimate
  belongs_to :service, optional: true

  validates :qty, numericality: { only_integer: true, greater_than: 0 }
  validates :cost_rate, :total, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :tax_rate, numericality: { greater_than_or_equal_to: 0, allow_nil: true }

  before_validation :set_defaults, :calculate_total

  # Returns the tax amount for this line item (rate * qty * tax_rate%)
  def tax_amount
    (cost_rate.to_d * qty.to_i) * (tax_rate.to_d / 100.0)
  end

  # Returns the line total including tax
  def total_with_tax
    total.to_d + tax_amount
  end

  private

  # Calculates the line item subtotal (before tax)
  # Note: The 'total' column represents the pre-tax line subtotal (qty * cost_rate).
  # Tax is calculated separately via tax_amount and added at the Estimate level.
  def calculate_total
    self.total = qty.to_i * cost_rate.to_d
  end

  def set_defaults
    self.tax_rate ||= 0.0
  end
end
