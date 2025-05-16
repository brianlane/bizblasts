# frozen_string_literal: true

class BusinessManager::Settings::SubscriptionsController < BusinessManager::BaseController
  # Standard actions that need tenant, user, business context, and API key
  before_action :set_business, except: [:webhook]
  before_action :set_subscription, only: [:show]
  before_action :set_stripe_api_key, only: [:create_checkout_session, :customer_portal_session, :webhook]

  # Webhook specific skips - it authenticates via Stripe signature and operates outside user session context
  skip_before_action :verify_authenticity_token, only: [:webhook]
  skip_before_action :authenticate_user!, only: [:webhook]
  skip_before_action :set_tenant_for_business_manager, only: [:webhook]
  skip_before_action :authorize_access_to_business_manager, only: [:webhook]
  # set_stripe_api_key is already covered by only/except. set_business is now covered by except.

  def show
    authorize @subscription || Subscription.new(business: @business), policy_class: Settings::SubscriptionPolicy
    # If @subscription is nil, the view should handle it gracefully (e.g., show "No active subscription")
  end

  # Initiates a Stripe Checkout session for a new subscription or changing plan
  def create_checkout_session
    authorize Subscription.new(business: @business), :new?, policy_class: Settings::SubscriptionPolicy
    # TODO: Determine price_id based on selected plan (e.g., from params or business tier)
    # For now, let's assume a placeholder price_id
    price_id = params[:price_id] || 'YOUR_STRIPE_PRICE_ID_HERE' # Replace with actual logic

    begin
      session = Stripe::Checkout::Session.create({
        payment_method_types: ['card'],
        line_items: [{
          price: price_id,
          quantity: 1,
        }],
        mode: 'subscription',
        success_url: business_manager_settings_subscription_url + '?session_id={CHECKOUT_SESSION_ID}',
        cancel_url: business_manager_settings_subscription_url,
        customer: @business.stripe_customer_id, # Assuming business model has stripe_customer_id
        client_reference_id: @business.id # To identify the business in webhook
      })
      redirect_to session.url, allow_other_host: true
    rescue Stripe::StripeError => e
      flash[:alert] = "Could not connect to Stripe: #{e.message}"
      redirect_to business_manager_settings_subscription_path
    end
  end

  # Redirects to Stripe Customer Portal
  def customer_portal_session
    authorize @business.subscription || Subscription.new(business: @business), :customer_portal_session?, policy_class: Settings::SubscriptionPolicy
    return_url = business_manager_settings_subscription_url

    begin
      portal_session = Stripe::BillingPortal::Session.create({
        customer: @business.stripe_customer_id, # Ensure business has stripe_customer_id
        return_url: return_url,
      })
      redirect_to portal_session.url, allow_other_host: true
    rescue Stripe::StripeError => e
      flash[:alert] = "Could not connect to Stripe: #{e.message}"
      redirect_to business_manager_settings_subscription_path
    end
  end

  # Handles Stripe webhook events
  def webhook
    # Ensure the Stripe API key is set - do this first to avoid any issues
    set_stripe_api_key
    
    payload = request.body.read
    sig_header = request.env['HTTP_STRIPE_SIGNATURE']
    
    # Corrected access to credentials using hash access and providing a default empty hash for stripe credentials
    stripe_credentials = Rails.application.credentials.stripe || {}
    endpoint_secret = stripe_credentials[:webhook_secret] || ENV['STRIPE_WEBHOOK_SECRET']
    
    Rails.logger.info("Processing webhook: payload length=#{payload.length}, signature=#{sig_header}")

    begin
      event = Stripe::Webhook.construct_event(
        payload, sig_header, endpoint_secret
      )
    rescue JSON::ParserError => e
      # Invalid payload
      Rails.logger.error("Webhook JSON parse error: #{e.message}")
      render json: { error: 'Invalid payload' }, status: :bad_request
      return
    rescue Stripe::SignatureVerificationError => e
      # Invalid signature
      Rails.logger.error("Webhook signature verification error: #{e.message}")
      render json: { error: 'Signature verification failed' }, status: :bad_request
      return
    end

    # Handle the event
    case event.type
    when 'checkout.session.completed'
      session = event.data.object # contains a Stripe::Checkout::Session
      Rails.logger.info("Processing checkout.session.completed: session_id=#{session.id}, client_ref=#{session.client_reference_id}")
      handle_checkout_session_completed(session)
    when 'invoice.paid'
      invoice = event.data.object # contains a Stripe::Invoice
      handle_invoice_paid(invoice)
    when 'invoice.payment_failed'
      invoice = event.data.object # contains a Stripe::Invoice
      handle_invoice_payment_failed(invoice)
    when 'customer.subscription.updated', 'customer.subscription.deleted', 'customer.subscription.created'
      subscription_event = event.data.object # contains a Stripe::Subscription
      handle_subscription_change(subscription_event)
    else
      Rails.logger.info("Unhandled webhook event type: #{event.type}")
    end

    render json: { message: :ok }, status: :ok
  end

  private

  def set_business
    @business = current_tenant # Assuming current_tenant is the business from BusinessManager::BaseController
    unless @business
      flash[:alert] = "Business not found."
      redirect_to root_path # Or some other appropriate path
    end
  end

  def set_subscription
    @subscription = @business.subscription # Assumes has_one :subscription on Business model
  end

  def set_stripe_api_key
    # Corrected access to credentials using hash access and providing a default empty hash for stripe credentials
    stripe_credentials = Rails.application.credentials.stripe || {}
    Stripe.api_key = stripe_credentials[:secret_key] || ENV['STRIPE_SECRET_KEY']
  end

  def handle_checkout_session_completed(session)
    # Retrieve the subscription details from the session if needed, or wait for subscription.created event
    # For example, if you need to create/update your local Subscription record here:
    business = Business.find_by(id: session.client_reference_id)
    stripe_subscription_id = session.subscription

    unless business && stripe_subscription_id
      Rails.logger.error("Cannot handle checkout.session.completed: business_id=#{session.client_reference_id}, stripe_sub_id=#{stripe_subscription_id}")
      return
    end

    # Fetch the subscription from Stripe to get all details
    stripe_sub = Stripe::Subscription.retrieve(stripe_subscription_id)
    
    Rails.logger.info("Creating/updating subscription for business_id=#{business.id}, stripe_sub_id=#{stripe_subscription_id}")

    subscription_record = business.subscription || business.build_subscription
    subscription_record.assign_attributes(
      plan_name: stripe_sub.items.data.first&.price&.lookup_key || stripe_sub.items.data.first&.price&.product, # or however you map plans
      stripe_subscription_id: stripe_sub.id,
      status: stripe_sub.status,
      current_period_end: Time.at(stripe_sub.current_period_end).to_datetime
    )
    
    if subscription_record.save
      Rails.logger.info("Successfully created/updated subscription id=#{subscription_record.id}")
    else
      Rails.logger.error("Failed to save subscription: #{subscription_record.errors.full_messages.join(', ')}")
    end

    # Update business tier if necessary
    # new_tier = map_stripe_plan_to_tier(stripe_sub.items.data.first&.price&.id)
    # business.update(tier: new_tier) if new_tier
  end

  def handle_invoice_paid(invoice)
    # Associated subscription ID is in invoice.subscription
    stripe_subscription_id = invoice.subscription
    return unless stripe_subscription_id

    stripe_sub = Stripe::Subscription.retrieve(stripe_subscription_id)
    business = Business.find_by(stripe_customer_id: stripe_sub.customer) # Or however you link Stripe customer to business
    return unless business

    subscription_record = business.subscription
    if subscription_record && subscription_record.stripe_subscription_id == stripe_sub.id
      subscription_record.update!(
        status: stripe_sub.status,
        current_period_end: Time.at(stripe_sub.current_period_end).to_datetime
      )
    end
  end

  def handle_invoice_payment_failed(invoice)
    stripe_subscription_id = invoice.subscription
    return unless stripe_subscription_id

    stripe_sub = Stripe::Subscription.retrieve(stripe_subscription_id)
    business = Business.find_by(stripe_customer_id: stripe_sub.customer)
    return unless business

    subscription_record = business.subscription
    if subscription_record && subscription_record.stripe_subscription_id == stripe_sub.id
      subscription_record.update!(status: stripe_sub.status) # Often 'past_due' or 'unpaid'
      # Potentially send notification to business owner
    end
  end

  def handle_subscription_change(stripe_sub)
    business = Business.find_by(stripe_customer_id: stripe_sub.customer)
    return unless business

    subscription_record = business.subscription || business.build_subscription
    # If it's a new subscription from an import or admin action, ensure business_id is set
    subscription_record.business_id ||= business.id

    subscription_record.assign_attributes(
      plan_name: stripe_sub.items.data.first&.price&.lookup_key || stripe_sub.items.data.first&.price&.product,
      stripe_subscription_id: stripe_sub.id,
      status: stripe_sub.status,
      current_period_end: Time.at(stripe_sub.current_period_end).to_datetime
    )
    subscription_record.save!

    # Update business tier if necessary
    # current_tier = map_stripe_plan_to_tier(stripe_sub.items.data.first&.price&.id)
    # business.update(tier: current_tier) if current_tier && business.tier != current_tier
  end
end 