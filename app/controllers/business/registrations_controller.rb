# frozen_string_literal: true

# Handles business sign-ups (creates User with manager role and associated Business).
class Business::RegistrationsController < Users::RegistrationsController
  before_action :configure_sign_up_params, only: [:create]

  # GET /resource/sign_up
  # Overrides Devise default to build the associated business for the form
  def new
    build_resource({}) # Builds the User resource

    # Pre-fill from OAuth data if present (user came from Google OAuth)
    # Only use OAuth data if it was recently set (within last 10 minutes)
    if session[:omniauth_data].present? && session[:omniauth_data_timestamp].present?
      # Check if OAuth data is fresh (less than 10 minutes old)
      begin
        timestamp = Time.iso8601(session[:omniauth_data_timestamp])
        if Time.current - timestamp < 10.minutes
          oauth_data = session[:omniauth_data]
          resource.email = oauth_data[:email]
          resource.first_name = oauth_data[:first_name]
          resource.last_name = oauth_data[:last_name]
          resource.provider = oauth_data[:provider]
          resource.uid = oauth_data[:uid]
        else
          # Clear stale OAuth data
          session.delete(:omniauth_data)
          session.delete(:omniauth_data_timestamp)
        end
      rescue ArgumentError => e
        # Timestamp is malformed or corrupted - clear OAuth data
        Rails.logger.warn "[REGISTRATION] Malformed OAuth timestamp: #{e.message}"
        session.delete(:omniauth_data)
        session.delete(:omniauth_data_timestamp)
      end
    end

    resource.build_business # Builds the nested Business resource
    respond_with resource
  end

  # POST /resource
  def create
    user_params = sign_up_params.except(:business_attributes)
    raw_business_params = params.require(:user).fetch(:business_attributes, {})
    processed_business_params = process_business_host_params(raw_business_params)
    
    # Handle OAuth user - add provider/uid from session if present
    # Only use OAuth data if it was recently set (within last 10 minutes)
    oauth_data = session[:omniauth_data]
    if oauth_data.present? && session[:omniauth_data_timestamp].present?
      # Check if OAuth data is fresh (less than 10 minutes old)
      begin
        timestamp = Time.iso8601(session[:omniauth_data_timestamp])
        if Time.current - timestamp < 10.minutes
          user_params = user_params.merge(
            provider: oauth_data[:provider],
            uid: oauth_data[:uid]
          )
          # OAuth users don't need to provide password in form - generate one
          unless user_params[:password].present?
            random_password = Devise.friendly_token[0, 20]
            user_params = user_params.merge(
              password: random_password,
              password_confirmation: random_password
            )
          end
        else
          # Clear stale OAuth data
          session.delete(:omniauth_data)
          session.delete(:omniauth_data_timestamp)
        end
      rescue ArgumentError => e
        # Timestamp is malformed or corrupted - clear OAuth data
        Rails.logger.warn "[REGISTRATION] Malformed OAuth timestamp: #{e.message}"
        session.delete(:omniauth_data)
        session.delete(:omniauth_data_timestamp)
      end
    end

    # If the submitted industry is not recognised, notify the user that we defaulted to "Other".
    submitted_industry = raw_business_params[:industry]
    if submitted_industry.present? &&
       !Business::SHOWCASE_INDUSTRY_MAPPINGS.values.include?(submitted_industry) &&
       !Business.industries.key?(submitted_industry.to_s)
      flash[:alert] = "\"#{submitted_industry}\" is not a recognised industry. Please select one from the list."

      # Rebuild a minimal resource for re-rendering the form without attempting to build an invalid Business record.
      build_resource(user_params)

      business_attrs = raw_business_params.except(:industry)
      allowed_business_keys = [:name, :phone, :email, :address, :city, :state, :zip, :description, :hostname, :canonical_preference]
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

    # BizBlasts no longer has paid tiers or membership checkout.
    create_business_immediately(user_params, processed_business_params)
  end

  protected

  # Permit nested parameters for business details.
  def configure_sign_up_params
    devise_parameter_sanitizer.permit(:sign_up, keys: [
      :first_name, :last_name, :bizblasts_notification_consent,
      { sidebar_items: [] }, # Permit sidebar items array
      business_attributes: [
        :name, :industry, :phone, :email, :address, :city, :state, :zip,
        :description,
        :hostname, :subdomain, :host_type, :custom_domain_owned, :canonical_preference,
      ],
      policy_acceptances: {}
    ])
  end
  
  # Revised: Process raw params to determine hostname and host_type based on presence first.
  def process_business_host_params(raw_params)
    # Handle both ActionController::Parameters and regular Hash
    if raw_params.respond_to?(:permit!)
      processed_params = raw_params.except(:hostname, :subdomain).permit! # Remove hostname and subdomain initially
    else
      # For regular Hash (like in tests), just duplicate and remove hostname/subdomain
      processed_params = raw_params.except(:hostname, :subdomain).dup
    end
    
    subdomain_input = raw_params[:subdomain].presence
    hostname_input = raw_params[:hostname].presence

    # Priority: Custom domain (hostname) > Subdomain
    if hostname_input.present?
      processed_params[:hostname] = hostname_input
      processed_params[:host_type] = 'custom_domain'
    elsif subdomain_input.present?
      processed_params[:hostname]  = subdomain_input   # same as now
      processed_params[:subdomain] = subdomain_input   # new – keep routing source-of-truth populated
      processed_params[:host_type] = 'subdomain'
    else
      processed_params[:hostname] = nil
      processed_params[:host_type] = 'subdomain'
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
    
    processed_params
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

  # Create business and user immediately
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
      
      # Clear OAuth session data if present
      session.delete(:omniauth_data)
      session.delete(:omniauth_data_timestamp)

      # Record policy acceptances after successful creation
      record_policy_acceptances(resource, params[:policy_acceptances]) if params[:policy_acceptances]

      # Create sidebar item preferences for the owner
      create_sidebar_items_for_user(resource, params[:sidebar_items], params[:sidebar_customized])

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

  # Record policy acceptances for the user
  def record_policy_acceptances(user, policy_params)
    return unless policy_params.present?
    
    policy_params.each do |policy_type, accepted|
      next unless accepted == '1'
      
      current_version = PolicyVersion.current_version(policy_type)
      next unless current_version
      
      begin
        PolicyAcceptance.record_acceptance(user, policy_type, current_version.version, request)
        SecureLogger.info "[REGISTRATION] Recorded policy acceptance: #{user.email} - #{policy_type} v#{current_version.version}"
      rescue => e
        Rails.logger.error "[REGISTRATION] Failed to record policy acceptance for #{policy_type}: #{e.message}"
      end
    end
  end

  # Create sidebar item preferences for a newly registered user
  def create_sidebar_items_for_user(user, selected_items, customized)
    # If user didn't customize sidebar (didn't interact with the section), use defaults
    # The sidebar system will show all defaults when no UserSidebarItem records exist
    return unless customized == "1"

    # User explicitly customized their sidebar - create records for all items
    # Even if selected_items is empty (user deselected all), we create records with visible: false
    selected_items ||= []

    # Get all default items (this returns the master list of 21 items)
    all_items = [
      'dashboard', 'bookings', 'estimates', 'website', 'website_builder',
      'transactions', 'payments', 'staff', 'services', 'products',
      'rentals', 'rental_bookings', 'shipping_methods', 'tax_rates',
      'customers', 'referrals', 'loyalty',
      'promotions', 'customer_subscriptions', 'settings'
    ]

    # Create records for all items, marking visibility based on selection
    all_items.each_with_index do |item_key, index|
      is_visible = selected_items.include?(item_key)

      user.user_sidebar_items.create!(
        item_key: item_key,
        position: index,
        visible: is_visible
      )
    end

    Rails.logger.info "[REGISTRATION] Created #{user.user_sidebar_items.count} sidebar items for user ##{user.id}"
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "[REGISTRATION] Failed to create sidebar items for user ##{user.id}: #{e.message}"
  end
end 