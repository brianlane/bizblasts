class ClientBookingsController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_client_user
  before_action :set_booking, only: [:show, :cancel]
  
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
    @booking = Booking.joins(:tenant_customer)
                     .where(tenant_customers: { email: current_user.email })
                     .find_by(id: params[:id])
  end
  
  def ensure_client_user
    unless current_user && current_user.client?
      redirect_to root_path, alert: "Only client users can access this area."
    end
  end
end 