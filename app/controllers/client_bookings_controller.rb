class ClientBookingsController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_client_user
  before_action :set_booking, only: [:show, :edit, :update, :cancel]
  before_action :ensure_booking_modifiable, only: [:edit, :update, :cancel]
  
  def index
    if on_business_domain?
      # Tenant-specific case: Show bookings only for this business
      current_business = ActsAsTenant.current_tenant
      if current_business
        @bookings = current_business.bookings.joins(:tenant_customer)
                                           .where(tenant_customers: { email: current_user.email })
                                           .includes(:service, :staff_member)
                                           .order(start_time: :desc)
      else
        @bookings = []
      end
    else
      # Main domain case: Show all bookings for this user across all businesses
      @bookings = Booking.joins(:tenant_customer)
                        .where(tenant_customers: { email: current_user.email })
                        .includes(:service, :staff_member, :business)
                        .order(start_time: :desc)
    end
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
                                      .select(&:visible_to_customers?) # Filter out hidden products
                                      .sort_by(&:name)
    # The view will use @booking.booking_product_add_ons to populate existing selections
  end
  
  def update
    # Enforce cancellation window policy on reschedule attempts
    permitted_attrs = client_booking_update_params
    if params[:booking][:start_time].present?
      policy_window = @booking.business.booking_policy&.cancellation_window_mins
      if policy_window.present? && policy_window > 0
        # Use local_start_time for consistent timezone comparison
        deadline = @booking.local_start_time - policy_window.minutes
        if Time.current > deadline
          if policy_window >= 60 && policy_window % 60 == 0
            hours = policy_window / 60
            time_unit = hours == 1 ? 'hour' : 'hours'
            alert_msg = "Cannot reschedule booking within #{hours} #{time_unit} of the start time."
          else
            alert_msg = "Cannot reschedule booking within #{policy_window} minutes of the start time."
          end
          redirect_to client_booking_path(@booking), alert: alert_msg and return
        end
      end
      begin
        new_start_time = Time.zone.parse(params[:booking][:start_time].to_s)
      rescue ArgumentError => e
        Rails.logger.warn "[CLIENT BOOKING] Invalid start_time provided: #{params[:booking][:start_time]} — #{e.message}"
        flash.now[:alert] = "Invalid start time format. Please choose a valid time."
        render :edit, status: :unprocessable_content and return
      end

      if new_start_time && @booking.service&.duration.present?
        # Build a safe, mutable copy of permitted params
        permitted_attrs = client_booking_update_params.to_h
        permitted_attrs[:end_time] = (new_start_time + @booking.service.duration.minutes).to_s
      else
        permitted_attrs = client_booking_update_params
      end
    end

    # --- Persist changes ---
    # We need to permit booking_product_add_ons_attributes for updates, including :id and :_destroy.
    if @booking.update(permitted_attrs)
      # After booking and add-ons are updated, regenerate/update the invoice
      generate_or_update_invoice_for_booking(@booking)
      NotificationService.booking_status_update(@booking)
      redirect_to client_booking_path(@booking), notice: 'Booking was successfully updated.'
    else
      # If update fails, re-render edit form. Need @available_products and @service again.
      @service = @booking.service
      @available_products = current_business_for_booking.products.active.includes(:product_variants)
                                        .where(product_type: [:service, :mixed])
                                        .where.not(product_variants: { id: nil })
                                        .select(&:visible_to_customers?) # Filter out hidden products
                                        .sort_by(&:name)
      flash.now[:alert] = @booking.errors.full_messages.to_sentence
      render :edit, status: :unprocessable_content
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
    success, error_message = BookingManager.cancel_booking(@booking, cancellation_reason, true, current_user: current_user)
    
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
      # Permit fields a client can change, including rescheduling times
      :notes,
      :start_time,
      :end_time,
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