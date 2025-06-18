class ClientBookingsController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_client_user
  before_action :set_booking, only: [:show, :edit, :update, :cancel]
  before_action :ensure_booking_modifiable, only: [:edit, :update, :cancel]
  
  def index
    # Get bookings for the current user across all businesses using tenant_customer email
    @bookings = Booking.joins(:tenant_customer)
                      .where(tenant_customers: { email: current_user.email })
                      .includes(:service, :staff_member, :business)
                      .order(start_time: :desc)
  end
  
  def show
    if @booking.nil?
      redirect_to client_bookings_path, alert: "Booking not found or you don't have permission to view it."
    end
  end
  
  def edit
    # @booking is set by before_action
    # Similar to Public::BookingController#new, fetch available products
    @service = @booking.service # Assuming booking always has a service
    # Fetch active products of type service or mixed for the current business to offer as add-ons
    @available_products = current_business_for_booking.products.active.includes(:product_variants)
                                      .where(product_type: [:service, :mixed])
                                      .where.not(product_variants: { id: nil })
                                      .order(:name)
    # The view will use @booking.booking_product_add_ons to populate existing selections
  end
  
  def update
    # @booking is set by before_action
    # We need to permit booking_product_add_ons_attributes for updates, including :id and :_destroy
    if @booking.update(client_booking_update_params)
      # After booking and add-ons are updated, regenerate/update the invoice
      generate_or_update_invoice_for_booking(@booking)
      redirect_to client_booking_path(@booking), notice: 'Booking was successfully updated.'
    else
      # If update fails, re-render edit form. Need @available_products and @service again.
      @service = @booking.service
      @available_products = current_business_for_booking.products.active.includes(:product_variants)
                                        .where(product_type: [:service, :mixed])
                                        .where.not(product_variants: { id: nil })
                                        .order(:name)
      flash.now[:alert] = @booking.errors.full_messages.to_sentence
      render :edit, status: :unprocessable_entity
    end
  end
  
  def cancel
    if @booking.nil?
      redirect_to client_bookings_path, alert: "Booking not found or you don't have permission to modify it."
      return
    end
    
    if @booking.start_time < Time.current
      redirect_to client_booking_path(@booking), alert: "Cannot cancel a past booking."
      return
    end
    
    if @booking.status == 'cancelled'
      redirect_to client_booking_path(@booking), notice: "This booking was already cancelled."
      return
    end
    
    # Use BookingManager to handle cancellation with policy checks
    cancellation_reason = "Cancelled by client"
    success, error_message = BookingManager.cancel_booking(@booking, cancellation_reason)
    
    if success
      redirect_to client_booking_path(@booking), notice: "Your booking has been successfully cancelled."
    else
      # Handle policy-based cancellation restrictions
      alert_message = error_message || "Unable to cancel this booking. Please try again."
      redirect_to client_booking_path(@booking), alert: alert_message
    end
  end
  
  private
  
  def set_booking
    # Security: Validate parameter before database query
    unless params[:id].present? && params[:id].to_i > 0
      Rails.logger.warn "[SECURITY] Invalid booking ID parameter in client bookings: #{params[:id]}, User: #{current_user&.email}, IP: #{request.remote_ip}"
      redirect_to client_bookings_path, alert: "Invalid booking ID." and return
    end

    # Security: Ensure booking is scoped to the current_user's tenant_customer records across all their businesses
    @booking = Booking.joins(:tenant_customer)
                     .where(tenant_customers: { email: current_user.email })
                     .includes(:service, :staff_member, :business, :tenant_customer, booking_product_add_ons: { product_variant: :product })
                     .find_by(id: params[:id])
    
    unless @booking
      # Security: Log unauthorized access attempts
      Rails.logger.warn "[SECURITY] Client attempted to access unauthorized booking: ID=#{params[:id]}, User=#{current_user.email}, IP=#{request.remote_ip}"
      redirect_to client_bookings_path, alert: "Booking not found." and return
    end
  end
  
  def ensure_client_user
    unless current_user && current_user.client?
      redirect_to root_path, alert: "Only client users can access this area."
    end
  end

  def ensure_booking_modifiable
    # Example: Allow modification only if booking is upcoming and not cancelled
    if @booking.start_time < Time.current || @booking.cancelled?
      redirect_to client_booking_path(@booking), alert: "This booking cannot be modified at this time."
    end
  end

  def current_business_for_booking
    # Helper to get the business context for the current @booking
    @booking.business
  end

  def client_booking_update_params
    params.require(:booking).permit(
      # Permit only fields a client can change, e.g., notes, product add-ons.
      # Start_time, staff_member_id might require re-validation of availability - complex for client edit.
      # For simplicity, let's assume clients can mainly change notes and product add-ons.
      # If they can change time/staff, more logic from Public::BookingController#create would be needed.
      :notes,
      booking_product_add_ons_attributes: {}
    )
  end

  # Copied and adapted from Public::BookingController - ensure it fits context
  def generate_or_update_invoice_for_booking(booking)
    invoice = booking.invoice || booking.build_invoice
    
    # Automatically assign the default tax rate if none provided
    default_tax_rate = booking.business.default_tax_rate
    
    invoice.assign_attributes(
      tenant_customer: booking.tenant_customer,
      business: booking.business,
      tax_rate: default_tax_rate, # Assign default tax rate for proper tax calculation
      due_date: booking.start_time.to_date,
      status: :pending 
    )
    invoice.save 
  end
end 