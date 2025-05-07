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
    @available_products = current_business_for_booking.products.active.includes(:product_variants)
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
    
    if @booking.update(status: :cancelled, cancellation_reason: "Cancelled by client")
      redirect_to client_booking_path(@booking), notice: "Your booking has been successfully cancelled."
    else
      redirect_to client_booking_path(@booking), alert: "Unable to cancel this booking. Please try again."
    end
  end
  
  private
  
  def set_booking
    # Ensure booking is scoped to the current_user's tenant_customer records across all their businesses
    # Or, if ClientBookingsController is always under a specific business context (e.g. via subdomain routing for client portal)
    # then scope to that current_tenant. For now, assuming it can be across businesses.
    tenant_customer_ids = current_user.tenant_customers.pluck(:id)
    @booking = Booking.where(tenant_customer_id: tenant_customer_ids)
                      .includes(:service, :staff_member, :business, :tenant_customer, booking_product_add_ons: {product_variant: :product} )
                      .find_by(id: params[:id])
    
    redirect_to client_bookings_path, alert: "Booking not found." unless @booking
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
      booking_product_add_ons_attributes: [:id, :product_variant_id, :quantity, :_destroy]
    )
  end

  # Copied and adapted from Public::BookingController - ensure it fits context
  def generate_or_update_invoice_for_booking(booking)
    invoice = booking.invoice || booking.build_invoice
    invoice.assign_attributes(
      tenant_customer: booking.tenant_customer,
      business: booking.business,
      due_date: booking.start_time.to_date,
      status: :pending 
    )
    invoice.save 
  end
end 