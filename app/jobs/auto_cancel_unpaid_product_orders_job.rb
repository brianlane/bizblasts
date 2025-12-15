class AutoCancelUnpaidProductOrdersJob < ApplicationJob
  queue_as :default

  PAYMENT_WINDOW = 4.hours

  def perform
    # Only apply to orders requiring payment
    Order.pending_payment.find_each do |order|
      # Skip pure service orders unless they have experience services
      next if order.order_type_service? && !order.has_experience_services?
      
      if Time.current > order.created_at + PAYMENT_WINDOW
        if order.is_mixed_order? && !order.has_experience_services?
          # For mixed orders without experience services, only cancel product components
          Rails.logger.info "[AutoCancelUnpaidProductOrdersJob] Partially cancelling mixed order #{order.id} - releasing product inventory only"
          
          # Release product inventory but keep service bookings
          order.stock_reservations.each do |reservation|
            reservation.product_variant.release_reservation!(reservation)
          end
          
          # Update order status to reflect partial cancellation
          order.update!(status: :cancelled, notes: "Product components cancelled due to non-payment. Service bookings remain active.")
        else
          # For pure product orders or orders with experience services, cancel entirely
          Rails.logger.info "[AutoCancelUnpaidProductOrdersJob] Fully cancelling order #{order.id}"
          
          # Release all reservations
          order.stock_reservations.each do |reservation|
            reservation.product_variant.release_reservation!(reservation)
          end
          
          order.update!(status: :cancelled)
        end
      end
    end
  end
end 