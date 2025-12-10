class ClientRentalBookingsController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_client_user
  before_action :set_rental_booking, only: [:show]

  def index
    @rental_bookings = if on_business_domain?
      business = ActsAsTenant.current_tenant
      if business
        business.rental_bookings
                .joins(:tenant_customer)
                .where(tenant_customers: { email: current_user.email })
                .includes(:product, :business, :location)
                .order(start_time: :desc)
      else
        RentalBooking.none
      end
    else
      ActsAsTenant.without_tenant do
        RentalBooking.joins(:tenant_customer)
                     .where(tenant_customers: { email: current_user.email })
                     .includes(:product, :business, :location)
                     .order(start_time: :desc)
      end
    end
  end

  def show
    @business = @rental_booking.business
  end

  private

  def ensure_client_user
    return if current_user&.client?
    redirect_to root_path, alert: "Only client users can access this area."
  end

  def set_rental_booking
    return if performed?

    @rental_booking = ActsAsTenant.without_tenant do
      RentalBooking.joins(:tenant_customer)
                   .where(tenant_customers: { email: current_user.email })
                   .includes(:product, :business, :location)
                   .find_by(id: params[:id])
    end
    return if @rental_booking

    redirect_to client_rental_bookings_path, alert: "Rental booking not found."
  end
end

