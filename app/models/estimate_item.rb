class EstimateItem < ApplicationRecord
  belongs_to :estimate
  belongs_to :service, optional: true

  validates :qty, numericality: { only_integer: true, greater_than: 0 }
  validates :cost_rate, :total, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :tax_rate, numericality: { greater_than_or_equal_to: 0, allow_nil: true }

  before_validation :set_defaults, :calculate_total

  def tax_amount
    (cost_rate.to_d * qty.to_i) * (tax_rate.to_d / 100.0)
  end

  private
  def calculate_total
    self.total = qty.to_i * cost_rate.to_d
  end

  def set_defaults
    self.tax_rate ||= 0.0
  end
end
