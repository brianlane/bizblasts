# frozen_string_literal: true

# Service for creating and managing rental bookings
#
# This service handles the business logic for rental bookings, including:
# - Availability validation
# - Price calculation
# - Booking creation and updates
# - Cancellation processing
#
# @example Creating a rental booking
#   service = RentalBookingService.new(
#     rental: rental_product,
#     tenant_customer: customer,
#     params: {
#       start_time: "2025-01-15 10:00",
#       end_time: "2025-01-17 10:00",
#       quantity: 1
#     }
#   )
#   result = service.create_booking
#   if result[:success]
#     booking = result[:booking]
#     # Redirect to payment if deposit required
#   end
#
# Follows patterns from BookingService and Estimate deposit flow
class RentalBookingService
  attr_reader :rental, :tenant_customer, :params, :business, :errors

  # Initialize the service with rental product, customer, and parameters
  #
  # @param rental [Product] the rental product (must have product_type: :rental)
  # @param tenant_customer [TenantCustomer] the customer making the booking
  # @param params [Hash] booking parameters (start_time, end_time, quantity, etc.)
  def initialize(rental:, tenant_customer:, params:)
    @rental = rental
    @tenant_customer = tenant_customer
    @params = params
    @business = rental.business
    @errors = []
  end

  # Create a new rental booking
  #
  # This method:
  # 1. Validates the rental product type
  # 2. Checks availability for the requested period
  # 3. Calculates pricing and security deposit
  # 4. Creates the RentalBooking record in pending_deposit status
  # 5. Does NOT create an invoice (deposit handled via Stripe Checkout)
  #
  # @return [Hash] result hash with keys:
  #   - :success [Boolean] whether the booking was created successfully
  #   - :booking [RentalBooking, nil] the created booking if successful
  #   - :errors [Array<String>] error messages if unsuccessful
  #
  # @example Successful creation
  #   result = service.create_booking
  #   #=> { success: true, booking: #<RentalBooking>, errors: [] }
  #
  # @example Failed creation
  #   result = service.create_booking
  #   #=> { success: false, booking: nil, errors: ["Rental not available"] }
  def create_booking
    @errors = []
    
    # Validate rental product
    unless rental.rental?
      @errors << "Product is not available for rental"
      return failure_response
    end
    
    # Validate availability
    unless check_availability
      return failure_response
    end
    
    # Create the booking
    booking = build_booking
    
    RentalBooking.transaction do
      if booking.save
        # Note: Security deposit is handled via Stripe checkout session
        # No invoice needed - deposit is collected before rental checkout
        success_response(booking)
      else
        @errors = booking.errors.full_messages
        failure_response
      end
    end
  rescue ActiveRecord::RecordInvalid => e
    @errors = [e.message]
    failure_response
  rescue StandardError => e
    Rails.logger.error("[RentalBookingService] Error creating booking: #{e.message}")
    Rails.logger.error(e.backtrace.first(5).join("\n"))
    @errors = ["An error occurred while creating the booking"]
    failure_response
  end
  
  # Update an existing rental booking
  #
  # Only allows updates for bookings in pending_deposit or deposit_paid status.
  # If dates are changed, re-validates availability (excluding the current booking).
  # Recalculates pricing if dates or quantity change.
  #
  # @param booking [RentalBooking] the booking to update
  # @return [Hash] result hash with keys:
  #   - :success [Boolean] whether the update was successful
  #   - :booking [RentalBooking] the updated booking
  #   - :errors [Array<String>] error messages if unsuccessful
  #
  # @raise [ArgumentError] if booking is already checked out
  #
  # @example Update rental dates
  #   result = service.update_booking(booking)
  #   #=> { success: true, booking: #<RentalBooking>, errors: [] }
  def update_booking(booking)
    @errors = []
    
    # Only allow updates for pending or deposit_paid bookings
    unless booking.status_pending_deposit? || booking.status_deposit_paid?
      @errors << "Cannot modify a booking that is already checked out"
      return failure_response
    end
    
    # If dates changed, check availability
    if params[:start_time].present? || params[:end_time].present? || params[:duration_mins].present?
      new_start = parse_time(params[:start_time]) || booking.start_time
      new_end = if params[:duration_mins].present?
                  new_start + params[:duration_mins].to_i.minutes
                else
                  parse_time(params[:end_time]) || booking.end_time
                end
      
      unless RentalAvailabilityService.available?(
        rental: rental,
        start_time: new_start,
        end_time: new_end,
        quantity: params[:quantity] || booking.quantity,
        exclude_booking_id: booking.id
      )
        @errors << "The rental is not available for the new dates"
        return failure_response
      end
    end
    
    if booking.update(update_params)
      success_response(booking)
    else
      @errors = booking.errors.full_messages
      failure_response
    end
  end
  
  # Cancel a rental booking
  #
  # Cancels a rental booking and processes deposit refund if applicable.
  # Only allowed for bookings in pending_deposit or deposit_paid status.
  #
  # @param booking [RentalBooking] the booking to cancel
  # @param reason [String, nil] optional cancellation reason (stored in notes)
  # @return [Hash] result hash with keys:
  #   - :success [Boolean] whether the cancellation was successful
  #   - :booking [RentalBooking] the cancelled booking
  #   - :errors [Array<String>] error messages if unsuccessful
  #
  # @example Cancel with reason
  #   result = service.cancel_booking(booking, reason: "Customer request")
  #   #=> { success: true, booking: #<RentalBooking status: 'cancelled'>, errors: [] }
  def cancel_booking(booking, reason: nil)
    @errors = []
    
    unless booking.can_cancel?
      @errors << "This booking cannot be cancelled"
      return failure_response
    end
    
    if booking.cancel!(reason: reason)
      success_response(booking)
    else
      @errors = booking.errors.full_messages
      failure_response
    end
  end
  
  private
  
  def check_availability
    start_time, end_time = requested_times
    quantity = (params[:quantity] || 1).to_i
    
    unless start_time && end_time
      @errors << "Start and end times are required"
      return false
    end
    
    if end_time <= start_time
      @errors << "End time must be after start time"
      return false
    end
    
    unless rental.valid_rental_duration?(start_time, end_time)
      @errors << "Rental duration does not meet the requirements (#{rental.rental_duration_display})"
      return false
    end
    
    unless RentalAvailabilityService.available?(
      rental: rental,
      start_time: start_time,
      end_time: end_time,
      quantity: quantity
    )
      @errors << "The rental is not available for the selected dates and quantity"
      return false
    end
    
    true
  end
  
  def build_booking
    start_time, end_time = requested_times
    
    rental.rental_bookings.build(
      business: business,
      tenant_customer: tenant_customer,
      product_variant_id: params[:product_variant_id],
      start_time: start_time,
      end_time: end_time,
      quantity: params[:quantity] || 1,
      rate_type: params[:rate_type],
      promotion_id: params[:promotion_id],
      location_id: params[:location_id] || rental.location_id,
      customer_notes: params[:customer_notes],
      notes: params[:notes],
      status: 'pending_deposit',
      deposit_status: 'pending'
    )
  end
  
  def update_params
    allowed = [:start_time, :end_time, :quantity, :customer_notes, :notes, :location_id]
    params.slice(*allowed)
  end
  
  def parse_time(value)
    return value if value.is_a?(Time) || value.is_a?(DateTime) || value.is_a?(ActiveSupport::TimeWithZone)
    return nil if value.blank?

    # Parse in business timezone context for consistency
    tz = business&.time_zone.presence || 'UTC'
    Time.use_zone(tz) { Time.zone.parse(value.to_s) }
  rescue ArgumentError
    nil
  end

  def requested_times
    start_time = parse_time(params[:start_time])
    end_time = if params[:duration_mins].present? && start_time.present?
                 start_time + params[:duration_mins].to_i.minutes
               else
                 parse_time(params[:end_time])
               end
    [start_time, end_time]
  end
  
  def success_response(booking)
    { success: true, booking: booking, errors: [] }
  end
  
  def failure_response
    { success: false, booking: nil, errors: @errors }
  end
end

