module Public
  class ClientBookingsController < ApplicationController
    before_action :authenticate_user!
    before_action :ensure_client_user
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
      
      if BookingService.cancel_booking(@booking, cancellation_reason)
        redirect_to tenant_my_booking_path(@booking), notice: "Your booking has been successfully cancelled."
      else
        redirect_to tenant_my_booking_path(@booking), alert: "Unable to cancel this booking. Please try again."
      end
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
    
    def ensure_client_user
      unless current_user && current_user.client?
        redirect_to tenant_root_path, alert: "Only client users can access this area."
      end
    end
  end
end 