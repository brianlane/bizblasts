# frozen_string_literal: true

module Public
  class OrdersController < ::OrdersController
    after_action :no_store!, only: %i[show]
    skip_before_action :authenticate_user!, only: [:new, :create, :show, :validate_promo_code]
    skip_before_action :set_current_tenant, only: [:new, :create, :show, :validate_promo_code]
    skip_before_action :set_tenant_customer,  only: [:new, :create, :show, :validate_promo_code]
    skip_before_action :verify_authenticity_token, only: [:validate_promo_code]
    before_action :set_tenant
    include BusinessAccessProtection
    before_action :check_business_user_checkout_access, only: [:new, :create]

    # GET /orders/new
    def new
      @cart  = CartManager.new(session).retrieve
      @order = OrderCreator.build_from_cart(@cart)
      @order.business      = current_tenant
      @order.tax_rate      = current_tenant.default_tax_rate
      # Recalculate totals after setting business and tax_rate
      @order.calculate_totals!
      
      # Handle customer selection for business users
      if current_user&.staff? || current_user&.manager?
        # Prepare nested customer for business users to select or create
        @order.build_tenant_customer
      else
        # Prepare nested customer for guest form
        @order.build_tenant_customer
      end
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
    
    # Handle customer identification based on user type (similar to booking logic)
    if current_user&.client?
      # Use CustomerLinker to ensure proper data sync
      begin
        linker = CustomerLinker.new(current_tenant)
        customer = linker.link_user_to_customer(current_user)
      rescue PhoneConflictError => e
        Rails.logger.error "[OrdersController#create] CustomerLinker phone conflict for user #{current_user.id}: #{e.message}"
        flash[:alert] = e.message
        redirect_to new_order_path and return
      rescue EmailConflictError => e
        Rails.logger.error "[OrdersController#create] CustomerLinker error for user #{current_user.id}: #{e.message}"
        flash[:alert] = e.message
        redirect_to new_order_path and return
      rescue StandardError => e
        Rails.logger.error "[OrdersController#create] CustomerLinker error for user #{current_user.id}: #{e.message}"
        flash[:alert] = "Unable to process order. Please try again."
        redirect_to new_order_path and return
      end

      creation_params = order_params.except(:tenant_customer_attributes, :create_account, :password, :password_confirmation)
      creation_params[:tenant_customer_id] = customer.id
      creation_params[:business_id]        = current_tenant.id
      
    elsif current_user.present? && (current_user.staff? || current_user.manager?)
      # Staff or manager: select or create tenant customer based on form inputs
      if order_params[:tenant_customer_id].present? && order_params[:tenant_customer_id] != 'new'
        customer = current_tenant.tenant_customers.find(order_params[:tenant_customer_id])
      else
        # Check if customer selection is required but missing
        nested = order_params[:tenant_customer_attributes] || {}
        if nested[:first_name].blank? && nested[:last_name].blank? && nested[:email].blank?
          flash[:alert] = "Please select a customer or provide customer details to place this order."
          redirect_to new_order_path and return
        end
        
        # Use CustomerLinker for guest customer management
        begin
          linker = CustomerLinker.new(current_tenant)
          customer = linker.find_or_create_guest_customer(
            nested[:email],
            first_name: nested[:first_name] || 'Unknown',
            last_name: nested[:last_name] || 'Customer',
            phone: nested[:phone],
            phone_opt_in: nested[:phone_opt_in] == 'true' || nested[:phone_opt_in] == true
          )
        rescue StandardError => e
          Rails.logger.error "[OrdersController#create] CustomerLinker error for staff/manager: #{e.message}"
          flash[:alert] = "Unable to process customer information. Please try again."
          redirect_to new_order_path and return
        end
      end
      
      creation_params = order_params.except(:tenant_customer_attributes, :create_account, :password, :password_confirmation)
      creation_params[:tenant_customer_id] = customer.id
      creation_params[:business_id]        = current_tenant.id
      
    else
      # Guest user: find or create TenantCustomer and optional account (existing logic)
      nested = order_params[:tenant_customer_attributes] || {}
      full_name = [nested[:first_name], nested[:last_name]].compact.join(' ')
      
      # Use CustomerLinker for guest customer management
      begin
        linker = CustomerLinker.new(current_tenant)
        customer = linker.find_or_create_guest_customer(
          nested[:email],
          first_name: nested[:first_name] || 'Unknown',
          last_name: nested[:last_name] || 'Customer',
          phone: nested[:phone],
          phone_opt_in: nested[:phone_opt_in] == 'true' || nested[:phone_opt_in] == true
        )
      rescue StandardError => e
        Rails.logger.error "[OrdersController#create] CustomerLinker error for guest: #{e.message}"
        flash[:alert] = "Unable to process customer information. Please try again."
        redirect_to new_order_path and return
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
        render :new, status: :unprocessable_content and return
      end # End of customer.save if/else

    end # End of guest user else block

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
          render :new, status: :unprocessable_content and return
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

      render :new, status: :unprocessable_content
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

    def validate_promo_code
      begin
        code = params[:promo_code]
        customer = current_user&.tenant_customer_for(current_tenant) || 
                   TenantCustomer.find_by(business: current_tenant, email: session[:guest_email])
        
        if code.blank?
          render json: { valid: false, error: 'Please enter a promo code' }
          return
        end

        result = PromoCodeService.validate_code(code, current_tenant, customer)
        
        if result[:valid]
          # Create a temporary order object to check item eligibility
          temp_order = build_temp_order_for_validation
          
          # Check if any items in the order are eligible for discounts
          unless PromoCodeService.send(:transaction_has_discount_eligible_items?, temp_order)
            render json: { valid: false, error: 'None of the items in this order are eligible for discount codes' }
            return
          end
          
          # Calculate discount amount based on eligible items only
          eligible_amount = PromoCodeService.send(:calculate_discount_eligible_amount, temp_order)
          if eligible_amount <= 0
            render json: { valid: false, error: 'No eligible items for discount' }
            return
          end
          
          discount_amount = PromoCodeService.calculate_discount(code, current_tenant, eligible_amount, customer)
          
          render json: { 
            valid: true, 
            type: result[:type],
            discount_amount: discount_amount,
            formatted_discount: ActionController::Base.helpers.number_to_currency(discount_amount),
            message: "Promo code applied! You'll save #{ActionController::Base.helpers.number_to_currency(discount_amount)}"
          }
        else
          render json: { valid: false, error: result[:error] }
        end
      rescue => e
        render json: { valid: false, error: 'An error occurred while validating the promo code. Please try again.' }
      end
    end

    private

    # Set Cache-Control headers to prevent caching
    def no_store!
      response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
      response.headers["Pragma"]        = "no-cache"
      response.headers["Expires"]       = "0"
    end

    # Build a temporary order object for promo code validation
    def build_temp_order_for_validation
      cart = CartManager.new(session).retrieve
      temp_order = OrderCreator.build_from_cart(cart)
      temp_order.business = current_tenant
      temp_order.tax_rate = current_tenant.default_tax_rate
      temp_order.calculate_totals!
      temp_order
    end

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
        :tenant_customer_id,
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

    # Check if business user should be blocked from checkout unless acting on behalf of customer
    def check_business_user_checkout_access
      return unless current_user.present?
      return unless current_tenant.present?
      
      guard = BusinessAccessGuard.new(current_user, current_tenant, session)
      
      if guard.should_block_own_business_checkout?
        # For GET requests (new), show the form but with customer selection required
        return if request.get?
        
        # For POST requests (create), check if customer was selected
        if params[:order] && (params[:order][:tenant_customer_id].blank? || params[:order][:tenant_customer_id] == '') &&
           (params[:order][:tenant_customer_attributes].blank? || 
            params[:order][:tenant_customer_attributes].values.all?(&:blank?))
          
          guard.log_blocked_checkout
          flash[:alert] = guard.checkout_flash_message
          redirect_to new_order_path and return
        end
      end
    end
  end
end