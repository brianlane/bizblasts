# frozen_string_literal: true

module Public
  class OrdersController < ::OrdersController
    skip_before_action :authenticate_user!, only: [:new, :create, :show]
    skip_before_action :set_current_tenant, only: [:new, :create, :show]
    skip_before_action :set_tenant_customer,  only: [:new, :create, :show]
    before_action :set_tenant

    # GET /orders/new
    def new
      @cart  = CartManager.new(session).retrieve
      @order = OrderCreator.build_from_cart(@cart)
      @order.business      = current_tenant
      @order.tax_rate      = current_tenant.default_tax_rate
      # Prepare nested customer for guest form
      @order.build_tenant_customer
    end

      # POST /orders
  def create
    # Extract tip amount if provided
    tip_amount = params[:tip_amount].to_f if params[:tip_amount].present?
    
    # Validate tip amount if provided
    if tip_amount.present? && tip_amount > 0
      if tip_amount < 0.50
        flash[:alert] = "Minimum tip amount is $0.50."
        redirect_to new_order_path and return
      end
    end

    @cart = CartManager.new(session).retrieve

      # Determine tenant_customer for this order
      if current_user&.client?
        customer = current_tenant.tenant_customers.find_or_create_by!(email: current_user.email) do |c|
          c.name  = current_user.full_name
          c.phone = current_user.phone
        end
      elsif current_user.present? && (current_user.staff? || current_user.manager?)
        if order_params[:tenant_customer_id].present?
          customer = current_tenant.tenant_customers.find(order_params[:tenant_customer_id])
        else
          nested   = order_params[:tenant_customer_attributes] || {}
          full_name = [nested[:first_name], nested[:last_name]].compact.join(' ')
          customer  = current_tenant.tenant_customers.create!(
            name:  full_name,
            phone: nested[:phone],
            email: nested[:email].presence
          )
        end
      else
        # Guest user - create or find customer
        nested = order_params[:tenant_customer_attributes] || {}
        full_name = [nested[:first_name], nested[:last_name]].compact.join(' ')
        
        # Try to find existing customer by email
        customer = current_tenant.tenant_customers.find_by(email: nested[:email])
        
        if customer
          # Update existing customer with new info if provided
          customer.update!(
            name: full_name.present? ? full_name : customer.name,
            phone: nested[:phone].present? ? nested[:phone] : customer.phone
          )
        else
          # Create new customer
          customer = current_tenant.tenant_customers.new(
            name:  full_name,
            phone: nested[:phone],
            email: nested[:email]
          )
        end

        # Handle account creation if requested
        if order_params[:create_account] == '1' && nested[:email].present?
          password = order_params[:password]
          password_confirmation = order_params[:password_confirmation]
          
          if password.present? && password == password_confirmation
            # Try to create user account
            user = User.new(
              email: nested[:email],
              password: password,
              password_confirmation: password_confirmation,
              first_name: nested[:first_name],
              last_name: nested[:last_name],
              phone: nested[:phone],
              role: :client
            )
            
            if user.save
              # Sign in the newly created user
              sign_in(user)
              flash[:notice] = 'Account created successfully!'
            else
              # If user creation fails, add errors to order
              user.errors.full_messages.each do |message|
                (@order || Order.new).errors.add(:base, "Account creation error: #{message}")
              end
            end
          else
            (@order || Order.new).errors.add(:base, "Password confirmation doesn't match password") if password != password_confirmation
            (@order || Order.new).errors.add(:base, "Password can't be blank") if password.blank?
          end
        end

        # Save customer (either new or updated existing)
        if customer.save
          # Now that we have the correct customer object (either found or created)
          # and optional user account is handled, proceed with order creation.
          creation_params = order_params.except(:tenant_customer_attributes, :create_account, :password, :password_confirmation)
          creation_params[:tenant_customer_id] = customer.id # Assign the customer ID to the order params
          creation_params[:business_id]        = current_tenant.id

        else # Customer.save failed
          # If customer save failed (e.g., validation error other than email uniqueness, though uniqueness should be handled by find_or_initialize_by)
          # Add customer errors to order errors and re-render
          customer.errors.full_messages.each do |message|
            (@order || Order.new).errors.add(:base, "Customer error: #{message}")
          end
          @order ||= OrderCreator.build_from_cart(@cart) # Build order for re-render if not already done
          @order.tenant_customer = customer # Assign the invalid customer to the order for form population
          flash.now[:alert] = @order.errors.full_messages.to_sentence
          render :new, status: :unprocessable_entity and return
        end # End of customer.save if/else

      end # End of guest user else block

      # Ensure creation_params is defined for client and staff users
      creation_params ||= order_params.except(:tenant_customer_attributes, :create_account, :password, :password_confirmation)
      creation_params[:tenant_customer_id] = customer.id
      creation_params[:business_id]        = current_tenant.id

      # Order creation happens here, outside the customer save conditional
      @order = OrderCreator.create_from_cart(@cart, creation_params)
      if @order.persisted? && @order.errors.empty?
        # Process promo code if provided
        if order_params[:promo_code].present?
          promo_result = PromoCodeService.validate_code(
            order_params[:promo_code], 
            current_tenant, 
            customer
          )
          
          if promo_result[:valid]
            @order.update!(
              applied_promo_code: order_params[:promo_code],
              promo_code_type: promo_result[:type],
              promo_discount_amount: PromoCodeService.calculate_discount(
                order_params[:promo_code], 
                current_tenant, 
                @order.total_amount, 
                customer
              )
            )
            
            # Apply the promo code
            PromoCodeService.apply_code(
              order_params[:promo_code],
              current_tenant,
              @order,
              customer
            )
          else
            @order.errors.add(:promo_code, promo_result[:error])
            flash.now[:alert] = @order.errors.full_messages.to_sentence
            render :new, status: :unprocessable_entity and return
          end
        end
        
        # Award loyalty points for order
        if current_tenant.loyalty_program_active?
          LoyaltyPointsService.award_order_points(@order)
        end
        
        # Update order with tip amount if provided
        if tip_amount.present? && tip_amount > 0
          @order.update!(tip_amount: tip_amount)
        end
        
        session[:cart] = {}
        
        # Create an invoice immediately
        invoice = @order.build_invoice(
          tenant_customer: @order.tenant_customer,
          business:       @order.business,
          due_date:       Date.today,
          status:         :pending
        )
        # Add tip amount to invoice if provided
        if tip_amount.present? && tip_amount > 0
          invoice.tip_amount = tip_amount
        end
        invoice.save!
        
        # Redirect directly to Stripe Checkout instead of payment page
        begin
          # Determine if this order has tip-eligible items
          tip_eligible_items = @order.tip_eligible_items
          
          success_url = if tip_eligible_items.any? && (invoice.tip_amount || 0) > 0
                          order_url(@order, payment_success: true, tip_included: true, host: request.host_with_port)
                        else
                          order_url(@order, payment_success: true, host: request.host_with_port)
                        end
          cancel_url = order_url(@order, payment_cancelled: true, host: request.host_with_port)
          
          result = StripeService.create_payment_checkout_session(
            invoice: invoice,
            success_url: success_url,
            cancel_url: cancel_url
          )
          
          redirect_to result[:session].url, allow_other_host: true
        rescue ArgumentError => e
          if e.message.include?("Payment amount must be at least")
            flash[:alert] = "This order amount is too small for online payment. Please contact the business directly."
            redirect_to order_path(@order)
          else
            raise e
          end
        rescue Stripe::StripeError => e
          flash[:alert] = "Could not connect to Stripe: #{e.message}"
          redirect_to order_path(@order)
        end
      else
        # If order creation failed, add order errors (which might include user/customer errors added above)
        flash.now[:alert] = @order.errors.full_messages.to_sentence if @order.errors.any?
        # Rebuild nested customer for re-render if needed (and not already assigned a found customer)
        @order.build_tenant_customer unless @order.tenant_customer.present?
        @order.tenant_customer ||= customer if customer.present? # Ensure customer is assigned back to the order for re-render

        render :new, status: :unprocessable_entity
      end
    end

    # GET /orders/:id  (guest view)
    def show
      # Security: Validate parameter before database query
      unless params[:id].present? && params[:id].to_i > 0
        Rails.logger.warn "[SECURITY] Invalid order ID parameter in public orders: #{params[:id]}, IP: #{request.remote_ip}"
        flash[:alert] = "Invalid order ID."
        redirect_to tenant_root_path and return
      end

      # Security: Proper scoping to current tenant to prevent cross-tenant access
      @order = Order.includes(line_items: :product_variant).find_by(id: params[:id], business_id: current_tenant.id)
      unless @order
        # Security: Log unauthorized access attempts
        Rails.logger.warn "[SECURITY] Attempted access to non-existent or unauthorized order: ID=#{params[:id]}, Tenant=#{current_tenant&.name}, IP=#{request.remote_ip}"
        flash[:alert] = 'Order not found'
        redirect_to tenant_root_path and return
      end

      # Security: Additional authorization check for logged-in users
      if current_user.present?
        unless user_can_view_order?(@order)
          Rails.logger.warn "[SECURITY] Unauthorized order access attempt: Order=#{@order.id}, User=#{current_user.email}, Customer=#{@order.tenant_customer&.email}, IP=#{request.remote_ip}"
          flash[:alert] = "You are not authorized to view this order."
          redirect_to tenant_root_path and return
        end
      else
        # For guest users, we'll allow access but log it for monitoring
        # Consider adding guest_access_token similar to invoices for better security
        Rails.logger.info "[ORDER] Guest access to order: Order=#{@order.id}, Customer=#{@order.tenant_customer&.email}, IP=#{request.remote_ip}"
      end
      
      # Renders public/orders/show which renders orders/show
    end

    private

    # Extend permitted params for guest checkout
    def order_params
      params.require(:order).permit(
        :shipping_method_id,
        :tax_rate_id,
        :shipping_address,
        :billing_address,
        :notes,
        :promo_code,
        :create_account,
        :password,
        :password_confirmation,
        tenant_customer_attributes: [:id, :first_name, :last_name, :email, :phone],
        line_items_attributes:     [:id, :product_variant_id, :quantity, :_destroy]
      )
    end

    # Security: Helper method to check if user can view order
    def user_can_view_order?(order)
      return false unless current_user.present?
      
      # Business staff/managers can view all orders for their business
      if current_user.staff? || current_user.manager?
        return current_user.business_id == order.business_id
      end
      
      # Clients can only view their own orders
      if current_user.client?
        return order.tenant_customer&.email == current_user.email
      end
      
      false
    end
  end
end