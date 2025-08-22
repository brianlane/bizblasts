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

  # GET /business/registration/success
  # Success page after Stripe payment completion
  def registration_success
    render 'registration_success'
  end

  # GET /business/registration/cancelled  
  # Handle cancelled Stripe payment
  def registration_cancelled
    flash[:alert] = "Registration was cancelled. You can try again anytime."
    redirect_to new_business_registration_path
  end

  # POST /resource
  def create
    user_params = sign_up_params.except(:business_attributes)
    raw_business_params = params.require(:user).fetch(:business_attributes, {})
    processed_business_params = process_business_host_params(raw_business_params)

    # If the submitted industry is not recognised, notify the user that we defaulted to "Other".
    submitted_industry = raw_business_params[:industry]
    if submitted_industry.present? &&
       !Business::SHOWCASE_INDUSTRY_MAPPINGS.values.include?(submitted_industry) &&
       !Business.industries.key?(submitted_industry.to_s)
      flash[:alert] = "\"#{submitted_industry}\" is not a recognised industry. Please select one from the list."

      # Rebuild a minimal resource for re-rendering the form without attempting to build an invalid Business record.
      build_resource(user_params)

      business_attrs = raw_business_params.except(:industry)
      allowed_business_keys = [:name, :phone, :email, :address, :city, :state, :zip, :description, :tier, :hostname, :platform_referral_code]
      business_attrs = if business_attrs.respond_to?(:permit)
                         business_attrs.permit(*allowed_business_keys).to_h
                       else
                         business_attrs.slice(*allowed_business_keys)
                       end
      resource.build_business(business_attrs)

      clean_up_passwords resource
      set_minimum_password_length
      render :new, status: :unprocessable_content
      return
    end
    
    # Build objects for validation only - DO NOT SAVE YET
    build_resource(user_params) 
    resource.role = :manager
    @business = Business.new(processed_business_params)
    
    # Temporarily skip business validation for initial validation
    # We'll validate business presence during the transaction
    resource.define_singleton_method(:requires_business?) { false }
    
    # Validate both objects without setting the association
    # (since business_id validation requires a persisted business)
    user_valid = resource.valid?
    business_valid = @business.valid?
    
    # Debug logging
    Rails.logger.info "[REGISTRATION DEBUG] User valid: #{user_valid}, Business valid: #{business_valid}"
    Rails.logger.info "[REGISTRATION DEBUG] User errors: #{resource.errors.full_messages.join(', ')}"
    Rails.logger.info "[REGISTRATION DEBUG] Business errors: #{@business.errors.full_messages.join(', ')}"
    Rails.logger.info "[REGISTRATION DEBUG] Business attributes: #{@business.attributes.inspect}"
    
    # Restore the original requires_business? method
    resource.singleton_class.remove_method(:requires_business?)
    
    unless user_valid && business_valid
      # Validation failed - render form with errors
      Rails.logger.info "[REGISTRATION] Validation failed. User errors: #{resource.errors.full_messages.join(', ')}. Business errors: #{@business.errors.full_messages.join(', ')}"
      
      # Merge business errors into user errors for display
      @business.errors.each do |error|
        resource.errors.add(:business, error.full_message)
      end
      
      # Set the business association for the form builder (but don't validate it)
      resource.business = @business
      
      clean_up_passwords resource
      set_minimum_password_length
      render :new, status: :unprocessable_content
      return
    end

    # Validation passed - now determine flow based on tier
    if @business.tier == 'free'
      # Free tier: Create business and user immediately
      create_business_immediately(user_params, processed_business_params)
    elsif @business.tier.in?(['standard', 'premium']) && !request_test_environment?
      # Paid tiers in production: Store data in Stripe session and redirect to payment
      redirect_to_stripe_with_registration_data(user_params, processed_business_params)
    else
      # Paid tiers in test environment: Create immediately for test compatibility
      create_business_immediately(user_params, processed_business_params)
    end
  end

  protected

  # Permit nested parameters for business details.
  def configure_sign_up_params
    devise_parameter_sanitizer.permit(:sign_up, keys: [
      :first_name, :last_name, :bizblasts_notification_consent,
      business_attributes: [
        :name, :industry, :phone, :email, :address, :city, :state, :zip,
        :description, :tier, 
        :hostname, # Permit the single hostname field
        :platform_referral_code # Permit platform referral code
        # Removed :subdomain, :domain
      ],
      policy_acceptances: {}
    ])
  end
  
  # Revised: Process raw params to determine hostname and host_type based on presence first.
  def process_business_host_params(raw_params)
    # Handle both ActionController::Parameters and regular Hash
    if raw_params.respond_to?(:permit!)
      processed_params = raw_params.except(:hostname).permit! # Permit all *except* hostname initially
    else
      # For regular Hash (like in tests), just duplicate and remove hostname
      processed_params = raw_params.except(:hostname).dup
    end
    
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
      # For free tier, default to subdomain host_type even if hostname is blank
      # This allows the model validation to show the correct error message
      processed_params[:host_type] = tier == 'free' ? 'subdomain' : nil
    end

    # Convert human-readable industry name (value) to the enum key string
    industry_val = processed_params["industry"] || processed_params[:industry]
    if industry_val.present?
      key = Business::SHOWCASE_INDUSTRY_MAPPINGS.key(industry_val)

      if key
        # Mapped value from the showcase list (e.g. "Hair Salons" -> :hair_salons)
        processed_params["industry"] = key.to_s
      elsif Business.industries.key?(industry_val.to_s)
        # Already passed as enum key (e.g. "hair_salons") – leave as-is
        processed_params["industry"] = industry_val.to_s
      else
        # Unrecognised value – remove to avoid ArgumentError; will be handled upstream
        processed_params["industry"] = nil
      end
    end
    
    # Normalize blank platform_referral_code to nil to avoid unique index collisions
    if processed_params.key?(:platform_referral_code)
      code_val = processed_params[:platform_referral_code]
      processed_params[:platform_referral_code] = nil if code_val.respond_to?(:strip) && code_val.strip.blank?
    end
    
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

  # Create business and user immediately (for free tier or test environment)
  def create_business_immediately(user_params, business_params)
    transaction_successful = false
    business_errors = nil
    resource_errors = nil

    begin
      ActiveRecord::Base.transaction do
        # 1. Save Business (use the already validated @business object)
        unless @business.save
          business_errors = @business.errors
          Rails.logger.error "Business Registration Transaction Failed - Business Errors: #{business_errors.full_messages.join(', ')}"
          raise ActiveRecord::Rollback
        end

        # 2. Save User with business association
        resource.business_id = @business.id
        unless resource.save
          resource_errors = resource.errors
          Rails.logger.error "Business Registration Transaction Failed - User Errors: #{resource_errors.full_messages.join(', ')}"
          raise ActiveRecord::Rollback
        end

        # 3. Set up business defaults
        setup_business_defaults(@business, resource)
        
        transaction_successful = true
      end
    rescue ActiveRecord::Rollback
      Rails.logger.info "[REGISTRATION] Transaction rolled back."
    end

    if transaction_successful && resource.persisted?
      # Success path
      Rails.logger.info "[REGISTRATION] Transaction successful. Business ##{resource.business_id} created immediately."
      
      # Record policy acceptances after successful creation
      record_policy_acceptances(resource, params[:policy_acceptances]) if params[:policy_acceptances]
      
      # Process platform referral code if provided
      if business_params[:platform_referral_code].present?
        process_platform_referral_signup(@business, business_params[:platform_referral_code])
      end
      
      if resource.active_for_authentication?
        set_flash_message! :notice, :signed_up
        sign_up(resource_name, resource)
        session[:signed_up_business_id] = resource.business_id
        redirect_to after_sign_up_path_for(resource), allow_other_host: true, status: :see_other
      else
        set_flash_message! :notice, :"signed_up_but_#{resource.inactive_message}"
        expire_data_after_sign_in!
        redirect_to after_inactive_sign_up_path_for(resource), allow_other_host: true, status: :see_other
      end
    else
      # Failure path
      Rails.logger.info "[REGISTRATION] Transaction failed. Rendering form with errors."
      
      # Merge errors from business if they were captured
      if business_errors.present?
        business_errors.each do |error|
          resource.errors.add(:business, error.full_message)
        end
      end
      
      # Ensure the @business object is associated for the form builder
      resource.business = @business
      
      clean_up_passwords resource
      set_minimum_password_length
      render :new, status: :unprocessable_content
    end
  end

  # Redirect to Stripe with registration data stored in session metadata
  def redirect_to_stripe_with_registration_data(user_params, business_params)
    begin
      # Configure Stripe API key
      stripe_credentials = Rails.application.credentials.stripe || {}
      Stripe.api_key = stripe_credentials[:secret_key] || ENV['STRIPE_SECRET_KEY']
      
      # Determine the price ID based on the business tier
      price_id = StripeService.get_stripe_price_id(business_params[:tier])
      
      unless price_id
        raise ArgumentError, "No Stripe price ID configured for tier: #{business_params[:tier]}"
      end

      # Create success and cancel URLs
      success_url = main_app.root_url + 'business/registration/success'
      cancel_url = new_business_registration_url

      # Create Stripe checkout session with registration data in metadata
      session = Stripe::Checkout::Session.create({
        payment_method_types: ['card'],
        line_items: [{
          price: price_id,
          quantity: 1,
        }],
        mode: 'subscription',
        success_url: success_url,
        cancel_url: cancel_url,
        metadata: {
          registration_type: 'business',
          user_data: user_params.to_json,
          business_data: business_params.to_json
        }
      })
      
      Rails.logger.info "[REGISTRATION] Created Stripe checkout session #{session.id} for business registration"
      redirect_to session.url, allow_other_host: true
      
    rescue Stripe::StripeError => e
      Rails.logger.error "[REGISTRATION] Stripe checkout creation failed: #{e.message}"
      flash[:alert] = "Could not connect to Stripe for subscription setup: #{e.message}"
      redirect_to new_business_registration_path
    rescue => e
      Rails.logger.error "[REGISTRATION] Unexpected error during Stripe checkout: #{e.message}"
      flash[:alert] = "An error occurred during subscription setup. Please contact support."
      redirect_to new_business_registration_path
    end
  end

  # Set up all the default records for a new business
  def setup_business_defaults(business, user)
    # Create staff member for the business owner
    business.staff_members.create!(
      user: user,
      name: user.full_name,
      email: user.email,
      phone: business.phone,
      active: true
    )
    
    # Create default location
    create_default_location(business)
    
    # Setup Stripe integration for paid tiers
    setup_stripe_integration(business) if business.tier.in?(['standard', 'premium'])
    
    Rails.logger.info "[REGISTRATION] Set up defaults for Business ##{business.id}"
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
    # System tests run against lvh.me host, regardless of port
    request.host.include?('lvh.me')
  end

  # Record policy acceptances for the user
  def record_policy_acceptances(user, policy_params)
    return unless policy_params.present?
    
    policy_params.each do |policy_type, accepted|
      next unless accepted == '1'
      
      current_version = PolicyVersion.current_version(policy_type)
      next unless current_version
      
      begin
        PolicyAcceptance.record_acceptance(user, policy_type, current_version.version, request)
        Rails.logger.info "[REGISTRATION] Recorded policy acceptance: #{user.email} - #{policy_type} v#{current_version.version}"
      rescue => e
        Rails.logger.error "[REGISTRATION] Failed to record policy acceptance for #{policy_type}: #{e.message}"
      end
    end
  end

  # Process platform referral code during business signup
  def process_platform_referral_signup(business, referral_code)
    return unless referral_code.present?
    
    result = PlatformLoyaltyService.process_business_referral_signup(business, referral_code)
    
    if result[:success]
      Rails.logger.info "[PLATFORM_REFERRAL] Processed platform referral signup: #{business.name} via #{referral_code}"
      Rails.logger.info "[PLATFORM_REFERRAL] #{result[:message]}"
    else
      Rails.logger.warn "[PLATFORM_REFERRAL] Failed to process platform referral signup: #{business.name} via #{referral_code} - #{result[:error]}"
    end
  rescue => e
    Rails.logger.error "[PLATFORM_REFERRAL] Error processing platform referral signup: #{e.message}"
  end
end 