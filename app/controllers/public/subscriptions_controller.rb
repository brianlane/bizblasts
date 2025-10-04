# frozen_string_literal: true

class Public::SubscriptionsController < Public::BaseController
  after_action :no_store!
  skip_before_action :authenticate_user!  # Allow guest access for subscription signups
  before_action :set_tenant, if: -> { before_action_business_domain_check }
  before_action :set_product_or_service, except: [:confirmation]
  before_action :ensure_subscriptions_enabled, except: [:confirmation]

  # GET /subscriptions/new
  def new
    @customer_subscription = current_business.customer_subscriptions.build
    @customer_subscription.product = @product if @product
    @customer_subscription.service = @service if @service
    
    # Get or create tenant customer for current user or guest
    @tenant_customer = find_or_initialize_tenant_customer
    @customer_subscription.tenant_customer = @tenant_customer
    
    # Calculate subscription pricing
    item = @product || @service
    @original_price = item&.price&.to_f || 0.0
    @subscription_price = item&.subscription_price&.to_f || 0.0
    @discount_amount = (@original_price - @subscription_price).round(2)
    @savings_percentage = @original_price > 0 ? ((@discount_amount / @original_price) * 100).round(1) : 0
    
    # Get available options for services
    if @service
      @staff_members = @service.staff_members.active
      @rebooking_preferences = CustomerSubscription.service_rebooking_preferences.keys
      @out_of_stock_actions = CustomerSubscription.out_of_stock_actions.keys
    end
    
    # Get product variants for products
    if @product
      @product_variants = @product.product_variants
      @out_of_stock_actions = CustomerSubscription.out_of_stock_actions.keys
    end
  end

  # POST /subscriptions
  def create
    # Ensure we have a tenant customer
    @tenant_customer = find_or_create_tenant_customer
    
    # Check if customer creation failed
    unless @tenant_customer
      flash.now[:alert] = 'Please provide valid customer information.'
      @customer_subscription = current_business.customer_subscriptions.build
      initialize_pricing_variables
      populate_form_data
      render :new, status: :unprocessable_content
      return
    end
    
    # Build subscription data for Stripe
    subscription_data = build_subscription_data(@tenant_customer)
    
    begin
      # Create Stripe checkout session
      stripe_result = StripeService.create_subscription_checkout_session(
        subscription_data: subscription_data,
        success_url: confirmation_subscription_url(id: 'SUBSCRIPTION_ID'),
        cancel_url: new_subscription_url(
          product_id: @product&.id,
          service_id: @service&.id
        )
      )
      
      if stripe_result[:success]
        # Redirect to Stripe Checkout
        redirect_to stripe_result[:session].url, allow_other_host: true
      else
        error_message = stripe_result[:error] || 'Unable to process subscription. Please try again.'
        
        # In development mode, show a more helpful message
        if Rails.env.development? && (error_message.include?('Stripe not configured') || error_message.include?('Stripe Connect not configured') || error_message.include?('Stripe Connect account not properly configured'))
          flash[:notice] = "✅ Subscription form is working! In production, this would redirect to Stripe Checkout for payment processing."
        else
          flash[:alert] = error_message
        end
        
        # Initialize pricing variables for the view
        @tenant_customer = find_or_initialize_tenant_customer
        @customer_subscription = current_business.customer_subscriptions.build
        initialize_pricing_variables
        
        populate_form_data
        render :new, status: :unprocessable_content
      end
      
    rescue => e
      Rails.logger.error "Subscription creation error: #{e.message}"
      flash[:alert] = 'Unable to process subscription. Please try again.'
      
      # Initialize pricing variables for the view
      @tenant_customer = find_or_initialize_tenant_customer
      @customer_subscription = current_business.customer_subscriptions.build
      initialize_pricing_variables
      
      populate_form_data
      render :new, status: :unprocessable_content
    end
  end

  # GET /subscriptions/:id/confirmation (hidden route for confirmation page)
  def confirmation
    # Handle both direct subscription ID and session-based confirmation
    if params[:id] && params[:id] != 'SUBSCRIPTION_ID'
      begin
        @customer_subscription = current_business.customer_subscriptions.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        redirect_to root_path, alert: 'Subscription not found.'
        return
      end
    elsif params[:session_id].present?
      # Find subscription by Stripe session (for post-checkout confirmation)
      @customer_subscription = find_subscription_by_session(params[:session_id])
    else
      redirect_to root_path, alert: 'Subscription not found.'
      return
    end
    
    # Verify access (either owns the subscription or has access token)
    unless can_access_subscription?(@customer_subscription)
      redirect_to root_path, alert: 'Access denied.'
    end
  end

  private

  def current_business
    ActsAsTenant.current_tenant
  end

  def set_product_or_service
    if params[:product_id].present?
      @product = current_business.products.active.find(params[:product_id])
      unless @product.subscription_enabled?
        redirect_to root_path, alert: 'Subscriptions not available for this product.'
      end
    elsif params[:service_id].present?
      @service = current_business.services.active.find(params[:service_id])
      unless @service.subscription_enabled?
        redirect_to root_path, alert: 'Subscriptions not available for this service.'
      end
    else
      redirect_to root_path, alert: 'Invalid subscription request.'
    end
  end

  def ensure_subscriptions_enabled
    unless current_business.subscription_discount_enabled?
      redirect_to root_path, alert: 'Subscriptions are not available.'
    end
  end

  def find_or_initialize_tenant_customer
    if user_signed_in?
      # Use CustomerLinker to ensure proper data sync for existing customers
      begin
        linker = CustomerLinker.new(current_business)
        linker.link_user_to_customer(current_user)
      rescue StandardError => e
        Rails.logger.error "[SubscriptionsController#find_or_initialize] CustomerLinker error for user #{current_user.id}: #{e.message}"
        # Fallback to build new customer for form display
        current_business.tenant_customers.build(
          first_name: current_user.first_name,
          last_name: current_user.last_name,
          email: current_user.email,
          phone: current_user.phone
        )
      end
    else
      # For guest checkout, we'll need to collect customer info
      current_business.tenant_customers.build
    end
  end

  def find_or_create_tenant_customer
    if user_signed_in?
      # Use CustomerLinker to ensure proper data sync
      begin
        linker = CustomerLinker.new(current_business)
        linker.link_user_to_customer(current_user)
      rescue CustomerLinker::EmailConflictError => e
        Rails.logger.error "[SubscriptionsController#find_or_create] CustomerLinker error for user #{current_user.id}: #{e.message}"
        return nil
      rescue StandardError => e
        Rails.logger.error "[SubscriptionsController#find_or_create] CustomerLinker error for user #{current_user.id}: #{e.message}"
        return nil
      end
    else
      # Use CustomerLinker for guest customer management
      customer_attrs = subscription_params[:tenant_customer_attributes] || {}
      begin
        linker = CustomerLinker.new(current_business)
        customer = linker.find_or_create_guest_customer(
          customer_attrs[:email],
          first_name: customer_attrs[:first_name],
          last_name: customer_attrs[:last_name],
          phone: customer_attrs[:phone],
          phone_opt_in: customer_attrs[:phone_opt_in] == 'true' || customer_attrs[:phone_opt_in] == true
        )

        # Return customer if created successfully, nil otherwise
        customer&.persisted? ? customer : nil
      rescue StandardError => e
        Rails.logger.error "[SubscriptionsController#find_or_create] CustomerLinker error for guest: #{e.message}"
        return nil
      end
    end
  end

  def can_access_subscription?(subscription)
    return false unless subscription.business == current_business
    
    if user_signed_in?
      subscription.tenant_customer.email == current_user.email
    else
      # For guest access, could implement token-based access
      params[:token].present? && params[:token] == subscription.access_token
    end
  end

  def initialize_pricing_variables
    item = @product || @service
    @original_price = item&.price&.to_f || 0.0
    @subscription_price = item&.subscription_price&.to_f || 0.0
    @discount_amount = (@original_price - @subscription_price).round(2)
    @savings_percentage = @original_price > 0 ? ((@discount_amount / @original_price) * 100).round(1) : 0
  end

  def populate_form_data
    return unless @customer_subscription
    
    @tenant_customer = @customer_subscription.tenant_customer
    @original_price = @customer_subscription.original_price
    @subscription_price = @customer_subscription.subscription_price
    @discount_amount = @customer_subscription.discount_amount
    @savings_percentage = @customer_subscription.savings_percentage
    
    if @service
      @staff_members = @service.staff_members.active
      @rebooking_preferences = CustomerSubscription.service_rebooking_preferences.keys
      @out_of_stock_actions = CustomerSubscription.out_of_stock_actions.keys
    end
    
    if @product
      @product_variants = @product.product_variants
      @out_of_stock_actions = CustomerSubscription.out_of_stock_actions.keys
    end
  end

  def subscription_params
    # Handle both nested and direct parameter formats
    if params[:customer_subscription].present?
      params.require(:customer_subscription).permit(
        :product_variant_id, :quantity, :billing_day_of_month,
        :service_rebooking_preference, :preferred_time_slot, :preferred_staff_member_id,
        :out_of_stock_action, :notes, :customer_rebooking_preference,
        tenant_customer_attributes: [:first_name, :last_name, :email, :phone, :address]
      )
    else
      # Handle direct parameters from the form
      params.permit(
        :product_id, :service_id, :product_variant_id, :quantity, :subscription_type,
        :billing_day_of_month, :service_rebooking_preference, :preferred_time_slot, 
        :preferred_staff_member_id, :out_of_stock_action, :notes, :customer_rebooking_preference
      )
    end
  end

  def build_subscription_data(tenant_customer)
    # Calculate pricing
    item = @product || @service
    original_price = item.price
    discount_percentage = current_business.subscription_discount_percentage || 0
    subscription_price = original_price * (1 - discount_percentage / 100.0)
    
    # Build customer preferences
    customer_preferences = {}
    
    if @product
      customer_preferences['preferred_variant_id'] = subscription_params[:product_variant_id] if subscription_params[:product_variant_id].present?
      customer_preferences['out_of_stock_action'] = subscription_params[:out_of_stock_action] if subscription_params[:out_of_stock_action].present?
    end
    
    if @service
      customer_preferences['preferred_staff_id'] = subscription_params[:preferred_staff_member_id] if subscription_params[:preferred_staff_member_id].present?
      customer_preferences['preferred_time_slot'] = subscription_params[:preferred_time_slot] if subscription_params[:preferred_time_slot].present?
      customer_preferences['service_rebooking_preference'] = subscription_params[:service_rebooking_preference] if subscription_params[:service_rebooking_preference].present?
    end
    
    {
      business_id: current_business.id,
      tenant_customer_id: tenant_customer.id,
      subscription_type: @product ? 'product' : 'service',
      item_id: item.id,
      item_name: item.name,
      quantity: subscription_params[:quantity]&.to_i || 1,
      frequency: 'monthly', # Default to monthly for now
      subscription_price: subscription_price,
      customer_preferences: customer_preferences
    }
  end

  def find_subscription_by_session(session_id)
    # This would require storing session ID in subscription record
    # For now, find the most recent subscription for the current customer
    if user_signed_in?
      tenant_customer = current_business.tenant_customers.find_by(email: current_user.email)
      tenant_customer&.customer_subscriptions&.order(created_at: :desc)&.first
    else
      # For guest users, this is more complex - would need session storage
      nil
    end
  end
end 