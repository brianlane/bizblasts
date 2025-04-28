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
        # Automatically create a StaffMember record linking this user to the new business
        resource.staff_memberships.create!(business: @business, name: resource.full_name)
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

      if resource.active_for_authentication?
        set_flash_message! :notice, :signed_up
        sign_up(resource_name, resource)
        after_sign_up_path = after_sign_up_path_for(resource)
        Rails.logger.info "[REGISTRATION] Sign up successful. Storing business ID #{committed_business.id} in session. Responding towards: #{after_sign_up_path}"
        session[:signed_up_business_id] = committed_business.id
        redirect_to after_sign_up_path, status: :see_other
      else
        set_flash_message! :notice, :"signed_up_but_#{resource.inactive_message}"
        expire_data_after_sign_in!
        redirect_to after_inactive_sign_up_path_for(resource), status: :see_other
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

  # Optional: Override path after sign up if needed
  # def after_sign_up_path_for(resource)
  #   # e.g., business_dashboard_path(hostname: resource.business.hostname)
  #   super(resource)
  # end
end 