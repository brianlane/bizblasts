# frozen_string_literal: true

# Controller for handling the public booking process within a tenant subdomain.
module Public
  class BookingController < Public::BaseController
    after_action :no_store!, only: %i[confirmation]
    # Ensure tenant is set based on subdomain
    before_action :set_tenant
    include BusinessAccessProtection
    # Ensure user is logged in to book (or handle guest booking flow)
    skip_before_action :authenticate_user!, only: [:new, :create, :confirmation]
    before_action :set_form_data, only: [:new, :create]
    # Use the business's time zone for date/time multiparam parsing in create
    around_action :use_business_time_zone, only: [:create]
    # Potentially allow viewing the form without login?

    # GET /book (new_booking_path)
    def new
      unless current_tenant
        Rails.logger.warn "[Public::BookingController#new] Tenant not set for request: #{request.host}"
        # tenant_not_found is likely called by set_tenant if it fails.
        return
      end

      @booking = current_tenant.bookings.new(service: @service)
      if params[:service_variant_id].present? && @service
        @service_variant = @service.service_variants.find_by(id: params[:service_variant_id])
        @booking.service_variant = @service_variant if @service_variant
      end
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
        current_tenant.ensure_time_zone! if current_tenant.respond_to?(:ensure_time_zone!)
        dt = BookingManager.process_datetime_params(params[:date], params[:start_time], current_tenant&.time_zone || 'UTC')
        @booking.start_time = dt if dt
      end
    end

    # POST /booking for guests, clients, and staff/managers
    # Note: Staff/managers creating bookings for clients will not be redirected to payment
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
          c.first_name = current_user.first_name
          c.last_name  = current_user.last_name
          c.phone      = current_user.phone
        end
      elsif current_user.present? && (current_user.staff? || current_user.manager?)
        # Staff or manager: select or create tenant customer based on form inputs
        if booking_params[:tenant_customer_id].present? && booking_params[:tenant_customer_id] != 'new'
          customer = current_tenant.tenant_customers.find(booking_params[:tenant_customer_id])
        else
          # Check if customer selection is required but missing
          nested = booking_params[:tenant_customer_attributes] || {}
          if nested[:first_name].blank? && nested[:last_name].blank? && nested[:email].blank?
            flash[:alert] = "Please select a customer or provide customer details to create a booking."
            redirect_to new_tenant_booking_path(service_id: booking_params[:service_id], staff_member_id: booking_params[:staff_member_id]) and return
          end
          
          # Try to find existing customer by email
          customer = current_tenant.tenant_customers.find_by(email: nested[:email])
          
          if customer
            # Update existing customer with new info if provided
            update_attrs = {}
            update_attrs[:first_name] = nested[:first_name] if nested[:first_name].present?
            update_attrs[:last_name] = nested[:last_name] if nested[:last_name].present?
            update_attrs[:phone] = nested[:phone] if nested[:phone].present?
            customer.update!(update_attrs) if update_attrs.any?
          else
            # Create new customer
            customer = current_tenant.tenant_customers.create!(
              first_name: nested[:first_name],
              last_name:  nested[:last_name],
              phone:      nested[:phone],
              email:      nested[:email].presence
            )
          end
        end
      else
        # Guest user: find or create TenantCustomer and optional account
        nested = booking_params[:tenant_customer_attributes] || {}
        
        # Check if required customer information is provided
        if nested[:first_name].blank? && nested[:last_name].blank? && nested[:email].blank?
          flash[:alert] = "Please provide your contact information to create a booking."
          redirect_to new_tenant_booking_path(service_id: booking_params[:service_id], staff_member_id: booking_params[:staff_member_id]) and return
        end
        
        # Try to find existing customer by email
        customer = current_tenant.tenant_customers.find_by(email: nested[:email])
        
        if customer
          # Update existing customer with new info if provided
          update_attrs = {}
          update_attrs[:first_name] = nested[:first_name] if nested[:first_name].present?
          update_attrs[:last_name] = nested[:last_name] if nested[:last_name].present?
          update_attrs[:phone] = nested[:phone] if nested[:phone].present?
          customer.update!(update_attrs) if update_attrs.any?
        else
          # Create new customer
          customer = current_tenant.tenant_customers.create!(
            first_name: nested[:first_name],
            last_name:  nested[:last_name],
            phone:      nested[:phone],
            email:      nested[:email].presence
          )
        end

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
                    :date, :duration, :promo_code
                 )
      @booking = current_tenant.bookings.new(attrs)
      @booking.tenant_customer = customer
      duration_for_booking = if @booking.service_variant.present?
                               @booking.service_variant.duration
                             else
                               @service.duration
                             end
      @booking.end_time        = @booking.start_time + duration_for_booking.minutes
      
      # Process promo code if provided
      if booking_params[:promo_code].present?
        promo_result = PromoCodeService.validate_code(
          booking_params[:promo_code], 
          current_tenant, 
          customer
        )
        
        if promo_result[:valid]
          @booking.applied_promo_code = booking_params[:promo_code]
          @booking.promo_code_type = promo_result[:type]
          @booking.promo_discount_amount = PromoCodeService.calculate_discount(
            booking_params[:promo_code], 
            current_tenant, 
            @booking.amount || @service.price, 
            customer
          )
        else
          @booking.errors.add(:promo_code, promo_result[:error])
        end
      end

      # Early validation for account creation errors
      if @booking.errors.any?
        flash.now[:alert] = @booking.errors.full_messages.to_sentence
        render :new, status: :unprocessable_entity and return
      end

      # Check if current user is business staff/manager making booking for client
      if current_user.present? && (current_user.staff? || current_user.manager?)
        # Business users creating bookings for clients - create booking immediately
        if @booking.save
          # Apply promo code if valid
          if @booking.applied_promo_code.present?
            PromoCodeService.apply_code(
              @booking.applied_promo_code,
              current_tenant,
              @booking,
              customer
            )
          end
          
          # Award loyalty points for booking
          if current_tenant.loyalty_program_active?
            LoyaltyPointsService.award_booking_points(@booking)
          end
          
          generate_or_update_invoice_for_booking(@booking)
          
          # Send business notification email
          begin
            BusinessMailer.new_booking_notification(@booking).deliver_later
            Rails.logger.info "[EMAIL] Scheduled business booking notification for Booking ##{@booking.id}"
          rescue => e
            Rails.logger.error "[EMAIL] Failed to schedule business booking notification for Booking ##{@booking.id}: #{e.message}"
          end
          
          flash[:notice] = "Booking was successfully created."
          redirect_to tenant_booking_confirmation_path(@booking)
        else
          flash.now[:alert] = @booking.errors.full_messages.to_sentence
          render :new, status: :unprocessable_entity
        end
      else
        # Client and guest users - validate booking but don't save yet for experience services
        # For standard services, save immediately and allow flexible payment
        if @service.experience?
          # Experience services require immediate payment - redirect to Stripe
          # Create a temporary invoice to calculate the total amount for Stripe
          temp_invoice = Invoice.new(
            tenant_customer: customer,
            business: current_tenant,
            due_date: @booking.start_time.to_date,
            status: :pending
          )
          
          # Calculate total amount including service and any add-ons
          service_amount = @service.price || 0
          addon_amount = 0
          
          if @booking.booking_product_add_ons.any?
            addon_amount = @booking.booking_product_add_ons.sum do |addon|
              variant = ProductVariant.find_by(id: addon.product_variant_id)
              next 0 unless variant
              
              base_price = variant.product.price || 0
              modifier = variant.price_modifier || 0
              final_price = base_price + modifier
              final_price * addon.quantity
            end
          end
          
          total_amount = service_amount + addon_amount
          temp_invoice.total_amount = total_amount
          
          # Prepare booking data for Stripe metadata
          booking_data = {
            service_id: @booking.service_id,
            staff_member_id: @booking.staff_member_id,
            start_time: @booking.start_time.iso8601,
            end_time: @booking.end_time.iso8601,
            notes: @booking.notes,
            tenant_customer_id: customer.id,
            booking_product_add_ons: @booking.booking_product_add_ons.map do |addon|
              {
                product_variant_id: addon.product_variant_id,
                quantity: addon.quantity
              }
            end
          }
          
          # Redirect directly to Stripe Checkout for experience services
          begin
            success_url = tenant_booking_confirmation_url('PENDING', payment_success: true, host: request.host_with_port)
            cancel_url = new_tenant_booking_url(service_id: @service.id, staff_member_id: @booking.staff_member_id, payment_cancelled: true, host: request.host_with_port)
            
            result = StripeService.create_payment_checkout_session_for_booking(
              invoice: temp_invoice,
              booking_data: booking_data,
              success_url: success_url,
              cancel_url: cancel_url
            )
            
            redirect_to result[:session].url, allow_other_host: true
          rescue ArgumentError => e
            if e.message.include?("Payment amount must be at least")
              flash[:alert] = "This booking amount is too small for online payment. Please contact the business directly."
              redirect_to new_tenant_booking_path(service_id: @service.id, staff_member_id: @booking.staff_member_id)
            else
              raise e
            end
          rescue Stripe::StripeError => e
            flash[:alert] = "Could not connect to Stripe: #{e.message}"
            redirect_to new_tenant_booking_path(service_id: @service.id, staff_member_id: @booking.staff_member_id)
          end
        else
          # Standard services allow flexible payment - create booking immediately
          if @booking.save
            # Apply promo code if valid
            if @booking.applied_promo_code.present?
              PromoCodeService.apply_code(
                @booking.applied_promo_code,
                current_tenant,
                @booking,
                customer
              )
            end
            
            # Award loyalty points for booking
            if current_tenant.loyalty_program_active?
              LoyaltyPointsService.award_booking_points(@booking)
            end
            
            # Generate invoice for the booking
            generate_or_update_invoice_for_booking(@booking)
            
            # Automatically confirm booking if no policy exists (legacy) or if policy allows it
            if current_tenant.booking_policy.nil? || current_tenant.booking_policy.auto_confirm_bookings?
              @booking.update!(status: :confirmed)
            end
            
            # Send business notification email for standard bookings too
            begin
              BusinessMailer.new_booking_notification(@booking).deliver_later
              Rails.logger.info "[EMAIL] Scheduled business booking notification for Booking ##{@booking.id}"
            rescue => e
              Rails.logger.error "[EMAIL] Failed to schedule business booking notification for Booking ##{@booking.id}: #{e.message}"
            end
            
            flash[:notice] = "Booking confirmed! You can pay now or later."
            redirect_to tenant_booking_confirmation_path(@booking)
          else
            flash.now[:alert] = @booking.errors.full_messages.to_sentence
            render :new, status: :unprocessable_entity
          end
        end
      end
    end

    # GET /booking/:id/confirmation (booking_confirmation_path)
    def confirmation
      unless current_tenant
        Rails.logger.warn "[Public::BookingController#confirmation] Tenant not set for request: #{request.host}"
        return
      end
      
      # Handle payment success for pending bookings
      if params[:id] == 'PENDING' && params[:payment_success] == 'true'
        # Payment was successful, booking should have been created by webhook
        # Show a generic success message and redirect to find their booking
        flash[:notice] = "Payment successful! Your booking has been confirmed."
        redirect_to tenant_root_path
        return
      end
      
      # Security: Validate parameter before database query
      unless params[:id].present? && (params[:id] == 'PENDING' || params[:id].to_i > 0)
        Rails.logger.warn "[SECURITY] Invalid booking ID parameter: #{params[:id]}, Tenant: #{current_tenant&.name}, IP: #{request.remote_ip}"
        flash[:alert] = "Invalid booking ID."
        redirect_to tenant_root_path and return
      end
      
      # Security: Ensure the booking belongs to the current tenant and add authorization
      @booking = current_tenant.bookings.find_by(id: params[:id])
      
      if @booking.nil?
        # Security: Log unauthorized access attempts
        Rails.logger.warn "[SECURITY] Attempted access to non-existent booking: ID=#{params[:id]}, Tenant=#{current_tenant&.name}, IP=#{request.remote_ip}"
        flash[:alert] = "Booking not found."
        redirect_to tenant_root_path and return
      end
      
      # Security: Additional authorization - ensure user has permission to view this booking
      if current_user.present?
        # If user is logged in, ensure they have permission to view this booking
        unless user_can_view_booking?(@booking)
          Rails.logger.warn "[SECURITY] Unauthorized booking access attempt: Booking=#{@booking.id}, User=#{current_user.email}, Customer=#{@booking.tenant_customer&.email}, IP=#{request.remote_ip}"
          flash[:alert] = "You are not authorized to view this booking."
          redirect_to tenant_root_path and return
        end
      else
        # For guest users, we'll allow access but this could be enhanced with additional verification
        # Consider adding guest_access_token similar to invoices for better security
        Rails.logger.info "[BOOKING] Guest access to booking confirmation: Booking=#{@booking.id}, IP=#{request.remote_ip}"
      end
      
      # Implicitly renders confirmation.html.erb
    end

    private

    # Wrap the action in the current tenant's time zone for correct multiparam time parsing
    def use_business_time_zone
      tz = current_tenant&.ensure_time_zone! || 'UTC'
      Time.use_zone(tz) { yield }
    end

    def set_form_data
      # Try to get service_id from top-level params (GET new) or nested booking params (POST create error)
      service_id = params[:service_id] || params[:booking].try(:[], :service_id)
      @service = current_tenant.services.find_by(id: service_id)
      if @service && params[:service_variant_id].present?
        @service_variant = @service.service_variants.find_by(id: params[:service_variant_id])
      end

      # Ensure @available_products is always set, even if @service is nil
      @available_products = if @service.present?
        current_tenant.products.active.includes(:product_variants)
                                 .where(product_type: [:service, :mixed])
                                 .where.not(product_variants: { id: nil }) # Only products with variants
                                 .select(&:visible_to_customers?) # Filter out hidden products
                                 .sort_by(&:name)
      else
        [] # Return an empty array if service is not found
      end
    end

    def booking_params
      params.require(:booking).permit(
        :service_id, :service_variant_id, :staff_member_id, :start_time,
        :'start_time(1i)', :'start_time(2i)', :'start_time(3i)',
        :'start_time(4i)', :'start_time(5i)', :quantity,
        :notes, :tenant_customer_id, :date, :duration, :promo_code,
        :create_account, :password, :password_confirmation,
        booking_product_add_ons_attributes: [:id, :product_variant_id, :quantity, :_destroy],
        tenant_customer_attributes: [:first_name, :last_name, :email, :phone]
      )
    end

    def generate_or_update_invoice_for_booking(booking)
      invoice = booking.invoice || booking.build_invoice
      
      # Automatically assign the default tax rate if none provided
      default_tax_rate = booking.business.default_tax_rate
      
      invoice.assign_attributes(
        tenant_customer: booking.tenant_customer,
        business: booking.business,
        tax_rate: default_tax_rate, # Assign default tax rate for proper tax calculation
        # Set other invoice attributes like due_date, status etc.
        # For now, ensure amounts are calculated based on booking and its add-ons
        due_date: booking.start_time.to_date, # Example due date
        status: :pending # Example status
        # invoice_number will be set by Invoice model callback if it has one
      )
      # The Invoice model's calculate_totals should sum service and booking_product_add_ons
      invoice.save! # This will trigger calculate_totals on the invoice
    end

    def current_tenant
      ActsAsTenant.current_tenant
    end

    # Security: Helper method to check if user can view booking
    def user_can_view_booking?(booking)
      return false unless current_user.present?
      
      # Business staff/managers can view all bookings for their business
      if current_user.staff? || current_user.manager?
        return current_user.business_id == booking.business_id
      end
      
      # Clients can only view their own bookings
      if current_user.client?
        return booking.tenant_customer&.email == current_user.email
      end
      
      false
    end
  end
end 