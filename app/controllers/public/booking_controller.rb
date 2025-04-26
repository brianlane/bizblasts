# frozen_string_literal: true

# Controller for handling the public booking process within a tenant subdomain.
module Public
  class BookingController < ApplicationController
    # Ensure tenant is set based on subdomain
    before_action :set_tenant
    # Ensure user is logged in to book (or handle guest booking flow)
    before_action :authenticate_user!, only: [:create] # Require login only for creating
    # Potentially allow viewing the form without login?

    # GET /book (new_booking_path)
    def new
      unless current_tenant
        Rails.logger.warn "[Public::BookingController#new] Tenant not set for request: #{request.host}"
        # tenant_not_found is likely called by set_tenant if it fails.
        return
      end

      @service = current_tenant.services.find_by(id: params[:service_id])
      if @service.nil?
        flash[:alert] = "Selected service not found or is not available."
        # Use specific helper for services page
        redirect_to tenant_services_page_path
        return
      end

      @booking = current_tenant.bookings.new(service: @service)
      # Pre-fill date/time and staff selection if provided via query params
      if params[:date].present? && params[:start_time].present?
        dt = BookingManager.process_datetime_params(params[:date], params[:start_time])
        @booking.start_time = dt if dt
      end
      @booking.staff_member_id = params[:staff_member_id] if params[:staff_member_id].present?
      # We might need to fetch available slots here or handle it via JS on the form.
      # For now, keep it simple.
    end

    # POST /booking (booking_index_path - Note: route helper might be booking_path if singular)
    def create
      unless current_tenant
        Rails.logger.warn "[Public::BookingController#create] Tenant not set for request: #{request.host}"
        render file: Rails.root.join('public/404.html'), layout: false, status: :not_found # Or redirect
        return
      end
      
      @service = current_tenant.services.find_by(id: booking_params[:service_id])
      if @service.nil?
        flash[:alert] = "Invalid service selected."
        # Use specific helper for new booking page
        redirect_to new_tenant_booking_path(service_id: booking_params[:service_id]), status: :unprocessable_entity
        return
      end

      # Find or create tenant customer based on the current user
      @tenant_customer = current_tenant.tenant_customers.find_or_create_by(
        email: current_user.email
      ) do |customer|
        customer.name = current_user.full_name
        customer.phone = current_user.phone if current_user.respond_to?(:phone)
      end
      
      # Add the tenant_customer_id to the booking params
      enhanced_params = booking_params.merge(
        tenant_customer_id: @tenant_customer.id,
        send_confirmation: false # Always send confirmation emails for public bookings
      )
      
      # Use the BookingManager directly to create the booking
      @booking, errors = BookingManager.create_booking(enhanced_params, current_tenant)

      if @booking
        flash[:notice] = "Booking created successfully!"
        # Use specific helper for confirmation page
        redirect_to tenant_booking_confirmation_path(@booking)
      else
        # Log detailed errors for debugging
        error_message = errors&.full_messages&.join(', ') || "Unknown error"
        Rails.logger.error "[Public::BookingController#create] Booking save failed: #{error_message}"
        flash.now[:alert] = "Booking failed: #{error_message}"
        
        # Initialize instance variables before re-rendering new
        @booking = current_tenant.bookings.new(booking_params)
        @service = current_tenant.services.find(booking_params[:service_id])
        @business = current_tenant
        
        # Re-render the form with errors  
        render :new, status: :unprocessable_entity
      end
    end

    # GET /booking/:id/confirmation (booking_confirmation_path)
    def confirmation
      unless current_tenant
        Rails.logger.warn "[Public::BookingController#confirmation] Tenant not set for request: #{request.host}"
        return
      end
      # Ensure the booking belongs to the current tenant
      @booking = current_tenant.bookings.find_by(id: params[:id])
      
      if @booking.nil?
        flash[:alert] = "Booking not found."
        redirect_to tenant_root_path # Or another appropriate path
      end
      # Implicitly renders confirmation.html.erb
    end

    private

    def booking_params
      params.require(:booking).permit(
        :service_id,
        :staff_member_id,
        :start_time,
        :"start_time(1i)",
        :"start_time(2i)", 
        :"start_time(3i)",
        :"start_time(4i)",
        :"start_time(5i)",
        :end_time,
        :"end_time(1i)",
        :"end_time(2i)", 
        :"end_time(3i)",
        :"end_time(4i)",
        :"end_time(5i)",
        :notes
      )
    end

    def current_tenant
      ActsAsTenant.current_tenant
    end
  end
end 