module Public
  class ClientBookingsController < ApplicationController
    before_action :authenticate_user!
    before_action :ensure_authorized_user
    before_action :set_business
    before_action :set_booking, only: [:show, :cancel]
    
    def index
      # Simplified query to avoid duplicates
      @bookings = Booking.where(business: @business)
                         .joins(:tenant_customer)
                         .where(tenant_customers: { email: current_user.email })
                         .includes(:service, :staff_member)
                         .order(start_time: :desc)
                         
      Rails.logger.debug "[Public::ClientBookingsController#index] Found #{@bookings.count} bookings for user #{current_user.id} at business #{@business.name}"
    end
    
    def show
      # Booking is set in before_action
      if @booking.nil?
        redirect_to tenant_my_bookings_path, alert: "Booking not found or you don't have permission to view it."
      end
    end
    
    def cancel
      if @booking.nil?
        redirect_to tenant_my_bookings_path, alert: "Booking not found or you don't have permission to modify it."
        return
      end
      
      unless @booking.can_cancel?
        reason = @booking.past? ? "Cannot cancel a past booking." : "This booking cannot be cancelled."
        redirect_to tenant_my_booking_path(@booking), alert: reason
        return
      end
      
      cancellation_reason = "Cancelled by client"
      
      success, error_message = BookingManager.cancel_booking(@booking, cancellation_reason, true, current_user: current_user)
      
      if success
        redirect_to tenant_my_booking_path(@booking), notice: "Your booking has been successfully cancelled."
      else
        alert_message = error_message || "Unable to cancel this booking. Please try again."
        redirect_to tenant_my_booking_path(@booking), alert: alert_message
      end
    end
    
    def create
      @booking = @business.bookings.new(booking_params)

      customer_id = params[:booking][:tenant_customer_id]
      customer_attrs = params[:booking][:tenant_customer_attributes]

      if customer_id.present? 
        @booking.tenant_customer = TenantCustomer.find(customer_id)
      elsif customer_attrs.present?
        @booking.tenant_customer = @business.tenant_customers.create(customer_attrs)
      end

      if @booking.save
        redirect_to tenant_my_booking_path(@booking), notice: 'Booking was successfully created.'
      else
        # TODO: Render booking form with errors
        render :new
      end
    end
    
    def booking_params
      params.require(:booking).permit(
        :start_time, :end_time, :notes, :service_id, :staff_member_id, :tenant_customer_id,
        tenant_customer_attributes: [:first_name, :last_name, :phone, :email]  
      )
    end
    
    private
    
    def set_booking
      @booking = Booking.where(business: @business)
                       .joins(:tenant_customer)
                       .where(tenant_customers: { email: current_user.email })
                       .find_by(id: params[:id])
    end
    
    def set_business
      # Find the business through the tenant setup from the subdomain
      @business = ActsAsTenant.current_tenant
      
      if @business
        Rails.logger.debug "[Public::ClientBookingsController] Business tenant found: #{@business.name} (ID: #{@business.id})"
      else
        # Try to find business via hostname
        hostname = request.subdomain
        @business = Business.find_by(hostname: hostname)
        
        if @business
          Rails.logger.debug "[Public::ClientBookingsController] Business found via hostname: #{@business.name} (ID: #{@business.id})"
          # Set the tenant for this request
          ActsAsTenant.current_tenant = @business
        else
          Rails.logger.error "[Public::ClientBookingsController] No business tenant found for subdomain: #{hostname}"
          # Create redirect URL to main domain
          base_domain = request.domain
          port_string = request.port == 80 || request.port == 443 ? '' : ":#{request.port}"
          redirect_url = "#{request.protocol}#{base_domain}#{port_string}/my-bookings"
          
          redirect_to redirect_url, allow_other_host: true, alert: "Unable to find business information."
          return false
        end
      end
    end
    
    def ensure_authorized_user
      unless current_user && (current_user.client? || (current_user.staff? && current_user.business == @business))
        redirect_to tenant_root_path, alert: "You are not authorized to access this area."
      end
    end
  end
end 