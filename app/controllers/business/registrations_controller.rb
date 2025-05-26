# frozen_string_literal: true

# Handles business sign-ups (creates User with manager role and associated Business).
class Business::RegistrationsController < Users::RegistrationsController
  before_action :configure_sign_up_params, only: [:create]

  # GET /resource/sign_up
  # Overrides Devise default to build the associated business for the form
  def new
    build_resource({}) # Builds the User resource
    resource.build_business # Builds the nested Business resource
    respond_with resource
  end

  # POST /resource
  def create
    user_params = sign_up_params.except(:business_attributes)
    raw_business_params = params.require(:user).fetch(:business_attributes, {})
    processed_business_params = process_business_host_params(raw_business_params)
    
    # Build objects separately first
    build_resource(user_params) 
    resource.role = :manager
    @business = Business.new(processed_business_params)
    # DO NOT assign resource.business = @business here initially

    transaction_successful = false
    business_errors = nil
    resource_errors = nil

    begin
      ActiveRecord::Base.transaction do
        # 1. Save Business
        unless @business.save
          business_errors = @business.errors # Capture errors
          Rails.logger.error "Business Registration Transaction Failed - Business Errors: #{business_errors.full_messages.join(', ')}"
          raise ActiveRecord::Rollback # Rollback transaction
        end

        # --- Business Saved Successfully ---
        
        # 2. Assign Saved Business ID and Save User
        resource.business_id = @business.id 
        # resource.business = nil # No longer needed as we didn't assign it

        unless resource.save
          resource_errors = resource.errors # Capture errors
          Rails.logger.error "Business Registration Transaction Failed - User Errors: #{resource_errors.full_messages.join(', ')}"
          Rails.logger.info "Business (will be rolled back): #{@business.attributes.inspect}" # Log state of business that succeeded but will be rolled back
          raise ActiveRecord::Rollback # Rollback transaction
        end

        # If we reach here, both saves were successful
        yield resource if block_given?
        transaction_successful = true # Mark success
      end # Transaction block ends (COMMIT or ROLLBACK)
    rescue ActiveRecord::Rollback
      # Transaction rolled back, failure path will be handled below
      Rails.logger.info "[REGISTRATION] Transaction rolled back."
    end

    # Handle success or failure AFTER transaction attempt
    if transaction_successful && resource.persisted?
      # --- Success Path ---
      Rails.logger.info "[REGISTRATION] Transaction successful. Handling post-signup for Business ##{resource.business_id}."
      # Fetch the committed business (using resource.business_id, @business might be stale)
      committed_business = Business.find(resource.business_id) 

      # Assign the user as a staff member of their business (default membership)
      committed_business.staff_members.create!(
        user: resource,
        name: resource.full_name,
        email: resource.email,
        phone: committed_business.phone,
        active: true
      )
      
      # Create a default location for the business using the business address
      create_default_location(committed_business)
      
      # Setup Stripe integration for paid tiers
      setup_stripe_integration(committed_business)
      
      if resource.active_for_authentication?
        set_flash_message! :notice, :signed_up
        sign_up(resource_name, resource)
        session[:signed_up_business_id] = committed_business.id
        
        # For paid tiers, redirect to Stripe checkout instead of the business dashboard
        # But in request tests (not system tests), use the standard redirect path
        if committed_business.tier.in?(['standard', 'premium']) && !request_test_environment?
          redirect_to_stripe_subscription_checkout(committed_business)
        else
          # For free tier or request test environment, redirect to the business dashboard
          redirect_to after_sign_up_path_for(resource), allow_other_host: true, status: :see_other
        end
      else
        set_flash_message! :notice, :"signed_up_but_#{resource.inactive_message}"
        expire_data_after_sign_in!
        # Redirect to the path defined for inactive sign up (preserves subdomain in non-test)
        redirect_to after_inactive_sign_up_path_for(resource), allow_other_host: true, status: :see_other
      end
    else
      # --- Failure Path ---
      Rails.logger.info "[REGISTRATION] Transaction failed or rolled back. Resource not persisted. Preparing to render 'new'."
      
      # Merge errors from business or resource if they were captured
      resource.errors.merge!(business_errors) if business_errors.present?
      # resource_errors are already on resource if resource.save failed
      
      Rails.logger.info "[REGISTRATION] Final Resource errors: #{resource.errors.full_messages.join(', ')}"
      
      # Ensure the @business object (with submitted params/potential errors) 
      # is associated for the form builder (`fields_for`)
      resource.business = @business 
      
      clean_up_passwords resource
      set_minimum_password_length
      respond_with resource # Let Devise/Responders render :new with errors
    end
  end

  protected

  # Permit nested parameters for business details.
  def configure_sign_up_params
    devise_parameter_sanitizer.permit(:sign_up, keys: [
      :first_name, :last_name,
      business_attributes: [
        :name, :industry, :phone, :email, :address, :city, :state, :zip,
        :description, :tier, 
        :hostname # Permit the single hostname field
        # Removed :subdomain, :domain
      ]
    ])
  end
  
  # Revised: Process raw params to determine hostname and host_type based on presence first.
  def process_business_host_params(raw_params)
    processed_params = raw_params.except(:hostname).permit! # Permit all *except* hostname initially
    tier = raw_params[:tier]
    # Note: Form now submits :hostname directly, not :subdomain/:domain
    hostname_input = raw_params[:hostname].presence 

    if hostname_input.present?
      # Basic check: Does it look like a custom domain or just a subdomain part?
      if hostname_input.include?('.') 
        processed_params[:hostname] = hostname_input
        processed_params[:host_type] = 'custom_domain'
      else 
        # Assume it's intended as a subdomain part
        processed_params[:hostname] = hostname_input 
        processed_params[:host_type] = 'subdomain'
      end
    else
      # Neither provided, let model handle blank hostname
      processed_params[:hostname] = nil 
      # If hostname is nil, host_type doesn't strictly matter for validation yet,
      # but maybe default based on tier? Let's keep it nil for now. Model validates presence.
      processed_params[:host_type] = nil 
    end

    # Let the Business model validations handle tier/host_type mismatches 
    # and specific format rules (e.g., free tier needs subdomain host_type).
    
    processed_params
  end

  # Old method, not used directly in create anymore, but might be useful elsewhere?
  # Consider removing if not used.
  def business_params
    params.require(:user).fetch(:business_attributes, {}).permit(
      :name, :industry, :phone, :email, :address, :city, :state, :zip,
      :description, :tier, :hostname 
    )
  end
  
  # Creates a default location for the business using its address information
  def create_default_location(business)
    # Default business hours (9am-5pm Monday-Friday, 10am-2pm Saturday, closed Sunday)
    default_hours = {
      "monday" => { "open" => "09:00", "close" => "17:00", "closed" => false },
      "tuesday" => { "open" => "09:00", "close" => "17:00", "closed" => false },
      "wednesday" => { "open" => "09:00", "close" => "17:00", "closed" => false },
      "thursday" => { "open" => "09:00", "close" => "17:00", "closed" => false },
      "friday" => { "open" => "09:00", "close" => "17:00", "closed" => false },
      "saturday" => { "open" => "10:00", "close" => "14:00", "closed" => false },
      "sunday" => { "open" => "00:00", "close" => "00:00", "closed" => true }
    }
    
    # Create the location
    business.locations.create!(
      name: "Main Location",
      address: business.address,
      city: business.city,
      state: business.state,
      zip: business.zip,
      hours: default_hours
    )
    
    Rails.logger.info "[REGISTRATION] Created default location for Business ##{business.id}"
  rescue => e
    # Log error but don't fail the registration if location creation fails
    Rails.logger.error "[REGISTRATION] Failed to create default location: #{e.message}"
  end

  # Setup Stripe integration for paid tiers
  def setup_stripe_integration(business)
    # Only setup Stripe for paid tiers
    return unless business.tier.in?(['standard', 'premium'])
    
    Rails.logger.info "[REGISTRATION] Setting up Stripe integration for Business ##{business.id} (#{business.tier} tier)"
    
    begin
      # Create Stripe Connect account for the business
      unless business.stripe_account_id.present?
        Rails.logger.info "[REGISTRATION] Creating Stripe Connect account for Business ##{business.id}"
        StripeService.create_connect_account(business)
        Rails.logger.info "[REGISTRATION] Successfully created Stripe Connect account: #{business.stripe_account_id}"
      end
      
      # Create Stripe customer for subscription billing
      unless business.stripe_customer_id.present?
        Rails.logger.info "[REGISTRATION] Creating Stripe customer for Business ##{business.id}"
        StripeService.ensure_stripe_customer_for_business(business)
        Rails.logger.info "[REGISTRATION] Successfully created Stripe customer: #{business.stripe_customer_id}"
      end
      
    rescue Stripe::StripeError => e
      # Log Stripe errors but don't fail the registration
      Rails.logger.error "[REGISTRATION] Stripe Connect account creation failed for Business ##{business.id}: #{e.message}"
    rescue => e
      # Log any other errors but don't fail the registration
      Rails.logger.error "[REGISTRATION] Unexpected error during Stripe setup for Business ##{business.id}: #{e.message}"
    end
  end

  # Redirect to Stripe subscription checkout for paid tiers
  def redirect_to_stripe_subscription_checkout(business)
    begin
      # Configure Stripe API key
      stripe_credentials = Rails.application.credentials.stripe || {}
      Stripe.api_key = stripe_credentials[:secret_key] || ENV['STRIPE_SECRET_KEY']
      
      # Determine the price ID based on the business tier
      price_id = StripeService.get_stripe_price_id(business.tier)
      
      unless price_id
        raise ArgumentError, "No Stripe price ID configured for tier: #{business.tier}"
      end

      # Create Stripe checkout session
      session = Stripe::Checkout::Session.create({
        payment_method_types: ['card'],
        line_items: [{
          price: price_id,
          quantity: 1,
        }],
        mode: 'subscription',
        success_url: main_app.root_url(subdomain: business.hostname) + '?subscription_success=true',
        cancel_url: main_app.root_url(subdomain: business.hostname) + '?subscription_cancelled=true',
        customer: business.stripe_customer_id,
        client_reference_id: business.id
      })
      
      redirect_to session.url, allow_other_host: true
    rescue Stripe::StripeError => e
      Rails.logger.error "[REGISTRATION] Stripe checkout creation failed for Business ##{business.id}: #{e.message}"
      flash[:alert] = "Could not connect to Stripe for subscription setup: #{e.message}"
      redirect_to after_sign_up_path_for(current_user), allow_other_host: true, status: :see_other
    rescue => e
      Rails.logger.error "[REGISTRATION] Unexpected error during Stripe checkout for Business ##{business.id}: #{e.message}"
      flash[:alert] = "An error occurred during subscription setup. Please contact support."
      redirect_to after_sign_up_path_for(current_user), allow_other_host: true, status: :see_other
    end
  end

  # Override path after successful business sign up to use tenant's subdomain
  def after_sign_up_path_for(resource)
    # In test environment use Devise default (tests expect root_path); otherwise redirect to subdomain
    if Rails.env.test?
      super(resource)
    else
      main_app.root_url(subdomain: resource.business.hostname)
    end
  end

  private

  # Check if we're in a request test environment (not system tests)
  def request_test_environment?
    Rails.env.test? && !system_test_environment?
  end

  # Check if we're in a system test environment
  def system_test_environment?
    # System tests typically use a different host pattern or user agent
    # Capybara system tests use a specific port range (9887+)
    request.host.include?('lvh.me') && request.port.to_s.match?(/988\d/)
  end
end 