class StockReservation < ApplicationRecord
  belongs_to :product_variant
  belongs_to :order
  
  validates :product_variant, :order, :quantity, :expires_at, presence: true
  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
  
  scope :expired, -> { where('expires_at < ?', Time.current) }

  after_commit :schedule_cleanup_job, on: :create

  def schedule_cleanup_job
    next_expiry = StockReservation.order(:expires_at).limit(1).pluck(:expires_at).first
    return unless next_expiry
    CleanupStockReservationsJob.set(wait_until: next_expiry + 2.minutes).perform_later
  end
end 