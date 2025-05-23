# frozen_string_literal: true

# Controller for handling the public booking process within a tenant subdomain.
module Public
  class BookingController < ApplicationController
    # Ensure tenant is set based on subdomain
    before_action :set_tenant
    # Ensure user is logged in to book (or handle guest booking flow)
    skip_before_action :authenticate_user!, only: [:new, :create, :confirmation]
    before_action :set_form_data, only: [:new, :create]
    # Potentially allow viewing the form without login?

    # GET /book (new_booking_path)
    def new
      unless current_tenant
        Rails.logger.warn "[Public::BookingController#new] Tenant not set for request: #{request.host}"
        # tenant_not_found is likely called by set_tenant if it fails.
        return
      end

      @booking = current_tenant.bookings.new(service: @service)
      # Always pre-fill staff member if provided via query params
      @booking.staff_member_id = params[:staff_member_id] if params[:staff_member_id].present?
      
      # If client user, set their own TenantCustomer; otherwise build nested for new customer
      if current_user && current_user.role == 'client' # Check current_user exists
        client_cust = current_tenant.tenant_customers.find_by(email: current_user.email)
        @booking.tenant_customer = client_cust if client_cust
      end
      # If still no tenant_customer (e.g. user not logged in, or not a client, or no record found)
      # The form might need fields for new customer details, handled by tenant_customer_attributes
      @booking.build_tenant_customer unless @booking.tenant_customer

      # Pre-fill date/time if provided via query params
      if params[:date].present? && params[:start_time].present?
        # Ensure BookingManager.process_datetime_params is robust
        dt = BookingManager.process_datetime_params(params[:date], params[:start_time])
        @booking.start_time = dt if dt
      end
    end

    # POST /booking for guests, clients, and staff/managers
    def create
      # Ensure tenant context
      unless current_tenant
        Rails.logger.warn "[Public::BookingController#create] Tenant not set for request: #{request.host}"
        render file: Rails.root.join('public/404.html'), layout: false, status: :not_found and return
      end

      # Validate service presence
      unless @service
        flash[:alert] = "Invalid service selected."
        redirect_to new_tenant_booking_path(service_id: booking_params[:service_id]), status: :unprocessable_entity and return
      end

      # Determine customer based on user state
      if current_user&.client?
        # Logged-in client: find or create their TenantCustomer by email
        customer = current_tenant.tenant_customers.find_or_create_by!(email: current_user.email) do |c|
          c.name  = current_user.full_name
          c.phone = current_user.phone
        end
      elsif current_user.present? && (current_user.staff? || current_user.manager?)
        # Staff or manager: select or create tenant customer based on form inputs
        if booking_params[:tenant_customer_id].present? && booking_params[:tenant_customer_id] != 'new'
          customer = current_tenant.tenant_customers.find(booking_params[:tenant_customer_id])
        else
          nested   = booking_params[:tenant_customer_attributes] || {}
          full_name = [nested[:first_name], nested[:last_name]].compact.join(' ')
          customer  = current_tenant.tenant_customers.create!(
            name:  full_name,
            phone: nested[:phone],
            email: nested[:email].presence
          )
        end
      else
        # Guest user: build a new TenantCustomer and optional account
        nested   = booking_params[:tenant_customer_attributes] || {}
        full_name = [nested[:first_name], nested[:last_name]].compact.join(' ')
        customer  = current_tenant.tenant_customers.create!(
          name:  full_name,
          phone: nested[:phone],
          email: nested[:email].presence
        )

        # Optionally create an account if requested
        if booking_params[:create_account] == '1' && booking_params[:password].present?
          user = User.new(
            email:                 nested[:email],
            first_name:            nested[:first_name],
            last_name:             nested[:last_name],
            phone:                 nested[:phone],
            password:              booking_params[:password],
            password_confirmation: booking_params[:password_confirmation],
            role:                  :client
          )
          if user.save
            ClientBusiness.create!(user: user, business: current_tenant)
            sign_in(user)
          else
            # Propagate user errors to booking
            user.errors.full_messages.each { |msg| (defined?(@booking) ? @booking : (@booking = current_tenant.bookings.new)).errors.add(:base, msg) }
          end
        end
      end

      # Build the booking with permitted attributes
      attrs     = booking_params.except(
                    :tenant_customer_id, :tenant_customer_attributes,
                    :create_account, :password, :password_confirmation,
                    :date, :duration
                 )
      @booking = current_tenant.bookings.new(attrs)
      @booking.tenant_customer = customer
      @booking.end_time        = @booking.start_time + @service.duration.minutes

      # Early validation for account creation errors
      if @booking.errors.any?
        flash.now[:alert] = @booking.errors.full_messages.to_sentence
        render :new, status: :unprocessable_entity and return
      end

      if @booking.save
        generate_or_update_invoice_for_booking(@booking)
        redirect_to tenant_booking_confirmation_path(@booking), notice: 'Booking was successfully created.'
      else
        flash.now[:alert] = @booking.errors.full_messages.to_sentence
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

    def set_form_data
      # Try to get service_id from top-level params (GET new) or nested booking params (POST create error)
      service_id = params[:service_id] || params[:booking].try(:[], :service_id)
      @service = current_tenant.services.find_by(id: service_id)

      # Ensure @available_products is always set, even if @service is nil
      @available_products = if @service.present?
        current_tenant.products.active.includes(:product_variants)
                                 .where(product_type: [:service, :mixed])
                                 .where.not(product_variants: { id: nil }) # Only products with variants
                                 .order(:name)
      else
        [] # Return an empty array if service is not found
      end
    end

    def booking_params
      params.require(:booking).permit(
        :service_id, :staff_member_id, :start_time,
        :'start_time(1i)', :'start_time(2i)', :'start_time(3i)',
        :'start_time(4i)', :'start_time(5i)', :quantity,
        :notes, :tenant_customer_id, :date, :duration,
        :create_account, :password, :password_confirmation,
        booking_product_add_ons_attributes: [:id, :product_variant_id, :quantity, :_destroy],
        tenant_customer_attributes: [:first_name, :last_name, :email, :phone]
      )
    end

    def generate_or_update_invoice_for_booking(booking)
      invoice = booking.invoice || booking.build_invoice
      invoice.assign_attributes(
        tenant_customer: booking.tenant_customer,
        business: booking.business,
        # Set other invoice attributes like due_date, status etc.
        # For now, ensure amounts are calculated based on booking and its add-ons
        due_date: booking.start_time.to_date, # Example due date
        status: :pending # Example status
        # invoice_number will be set by Invoice model callback if it has one
      )
      # The Invoice model's calculate_totals should sum service and booking_product_add_ons
      invoice.save # This will trigger calculate_totals on the invoice
    end

    def current_tenant
      ActsAsTenant.current_tenant
    end
  end
end 