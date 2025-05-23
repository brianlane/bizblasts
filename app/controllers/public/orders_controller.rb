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
        nested = order_params[:tenant_customer_attributes] || {}
        email = nested[:email].presence
        full_name = [nested[:first_name], nested[:last_name]].compact.join(' ')

        # Use find_or_initialize_by to find or build the tenant customer
        customer = current_tenant.tenant_customers.find_or_initialize_by(email: email)

        # Assign other attributes if it's a new record or if attributes are missing
        if customer.new_record?
           customer.assign_attributes(name: full_name, phone: nested[:phone])
        # Optionally update existing customer attributes if needed:
        # else
        #   customer.assign_attributes(name: full_name, phone: nested[:phone])
        end

        # Save the customer. This will run validations.
        if customer.save
           # Customer successfully found or created and saved

           # Now, proceed with optional user account creation if requested
           if order_params[:create_account] == '1' && order_params[:password].present?
             # Create or update the User account for this guest
             user = User.find_or_initialize_by(email: email)
             user.assign_attributes(
               email:                 email,
               first_name:            nested[:first_name],
               last_name:             nested[:last_name],
               phone:                 nested[:phone],
               password:              order_params[:password],
               password_confirmation: order_params[:password_confirmation],
               role:                  :client
             )
             if user.save
               # Link the user to the business as a client
               ClientBusiness.find_or_create_by!(user: user, business: current_tenant)
               sign_in(user)
             else
               user.errors.full_messages.each { |msg| (@order || Order.new).errors.add(:base, "Account creation error: #{msg}") }
             end
           end

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
        session[:cart] = {}
        redirect_to order_path(@order), notice: 'Order was successfully created.'
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
      @order = Order.includes(line_items: :product_variant).find_by(id: params[:id], business_id: current_tenant.id)
      unless @order
        flash[:alert] = 'Order not found'
        redirect_to tenant_root_path and return
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
        :create_account,
        :password,
        :password_confirmation,
        tenant_customer_attributes: [:id, :first_name, :last_name, :email, :phone],
        line_items_attributes:     [:id, :product_variant_id, :quantity, :_destroy]
      )
    end
  end
end