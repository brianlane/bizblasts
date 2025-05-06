class CleanupStockReservationsJob < ApplicationJob
  queue_as :default

  def perform
    StockReservation.expired.find_each do |reservation|
      reservation.product_variant.release_reservation!(reservation)
    end

    # Schedule next cleanup if there are still reservations
    next_expiry = StockReservation.order(:expires_at).limit(1).pluck(:expires_at).first
    if next_expiry && next_expiry > Time.current
      CleanupStockReservationsJob.set(wait_until: next_expiry + 2.minutes).perform_later
    end
  end
end 