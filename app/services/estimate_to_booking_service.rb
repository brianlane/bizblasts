# frozen_string_literal: true

class EstimateToBookingService
  def initialize(estimate)
    @estimate = estimate
  end

  def call
    return @estimate.booking if @estimate.booking.present?

    ActiveRecord::Base.transaction do
      # Create Booking based on the estimate
      booking = Booking.create!(
        business: estimate.business,
        tenant_customer: estimate.tenant_customer,
        start_time: estimate.proposed_start_time,
        # Use start_time + service duration from first item if available
        end_time: calculate_end_time,
        service: primary_service,
        quantity: total_quantity,
        amount: estimate.subtotal,
        original_amount: estimate.subtotal,
        discount_amount: 0,
        status: :pending
      )

      # Associate booking with estimate
      estimate.update!(booking: booking)

      # Create Invoice for the booking based on the remaining balance
      Invoice.create_from_estimate(estimate)

      booking
    end
  end

  private

  attr_reader :estimate

  # Returns the primary service for the booking (first line item)
  def primary_service
    estimate.estimate_items.first&.service
  end

  # Calculates end_time: use proposed_start_time + primary_service.duration if present
  def calculate_end_time
    start = estimate.proposed_start_time
    duration = primary_service&.duration.to_i
    start + duration.minutes if start
  end

  # Sum of all quantities in line items
  def total_quantity
    estimate.estimate_items.sum(&:qty)
  end
end 