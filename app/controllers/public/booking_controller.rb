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
      # Always pre-fill staff member if provided via query params
      @booking.staff_member_id = params[:staff_member_id] if params[:staff_member_id].present?
      # If client user, set their own TenantCustomer; otherwise build nested for new customer
      if current_user.role == 'client'
        client_cust = current_tenant.tenant_customers.find_by(email: current_user.email)
        @booking.tenant_customer = client_cust if client_cust
      else
        @booking.build_tenant_customer
      end
      # Pre-fill date/time if provided via query params
      if params[:date].present? && params[:start_time].present?
        dt = BookingManager.process_datetime_params(params[:date], params[:start_time])
        @booking.start_time = dt if dt
      end
      # We might need to fetch available slots here or handle it via JS on the form.
      # For now, keep it simple.
    end

    # POST /booking for business staff/managers
    def create
      unless current_tenant
        Rails.logger.warn "[Public::BookingController#create] Tenant not set for request: #{request.host}"
        render file: Rails.root.join('public/404.html'), layout: false, status: :not_found and return
      end

      @service = current_tenant.services.find_by(id: booking_params[:service_id])
      unless @service
        flash[:alert] = "Invalid service selected."
        redirect_to new_tenant_booking_path(service_id: booking_params[:service_id]), status: :unprocessable_entity and return
      end

      # Only staff/managers and clients can create bookings here
      unless current_user.staff? || current_user.manager? || current_user.client?
        redirect_to tenant_root_path, alert: 'You are not authorized to create bookings.' and return
      end

      # For client users, always use (or create) their TenantCustomer by email
      if current_user.client?
        customer = current_tenant.tenant_customers.find_or_create_by!(email: current_user.email) do |c|
          c.name = current_user.email.split('@').first.titleize
          c.phone = nil
        end
      else
        # Build or find customer (treat 'new' as creating a new record)
        if booking_params[:tenant_customer_id].present? && booking_params[:tenant_customer_id] != 'new'
          customer = current_tenant.tenant_customers.find(booking_params[:tenant_customer_id])
        else
          nested = booking_params[:tenant_customer_attributes] || {}
          customer = current_tenant.tenant_customers.create(
            name: nested[:name],
            phone: nested[:phone],
            email: nested[:email].presence
          )
        end
      end

      # Mass-assign all permitted booking params (including multi-parameter start_time), except customer info
      attrs = booking_params.except(:tenant_customer_id, :tenant_customer_attributes)
      @booking = current_tenant.bookings.new(attrs)
      @booking.tenant_customer = customer
      # Auto-calculate end_time based on the service duration
      @booking.end_time = @booking.start_time + @service.duration.minutes

      if @booking.save
        redirect_to tenant_booking_confirmation_path(@booking), notice: 'Booking was successfully created.'
      else
        flash.now[:alert] = @booking.errors.full_messages.to_sentence
        # Don't reset @booking—render the invalid record with errors so client fields persist
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
        :notes,
        :tenant_customer_id,
        tenant_customer_attributes: [:name, :email, :phone]
      )
    end

    def current_tenant
      ActsAsTenant.current_tenant
    end
  end
end 