# frozen_string_literal: true

class BusinessManager::Settings::BusinessController < BusinessManager::BaseController
  before_action :set_business
  before_action :authorize_business_settings # Pundit authorization

  # POST /manage/settings/business/connect_stripe
  def connect_stripe
    begin
      # Create Connect account if not existing
      StripeService.create_connect_account(@business) unless @business.stripe_account_id.present?
      # Generate onboarding link
      link = StripeService.create_onboarding_link(
        @business,
        refresh_url: refresh_stripe_business_manager_settings_business_url(host: request.host, protocol: request.protocol),
        return_url: edit_business_manager_settings_business_url(host: request.host, protocol: request.protocol)
      )
      redirect_to link.url, allow_other_host: true
    rescue Stripe::StripeError => e
      flash[:alert] = "Could not connect to Stripe: #{e.message}"
      redirect_to edit_business_manager_settings_business_path
    end
  end

  # GET /manage/settings/business/stripe_onboarding
  def stripe_onboarding
    link = StripeService.create_onboarding_link(
      @business,
      refresh_url: refresh_stripe_business_manager_settings_business_url(host: request.host, protocol: request.protocol),
      return_url: edit_business_manager_settings_business_url(host: request.host, protocol: request.protocol)
    )
    redirect_to link.url, allow_other_host: true
  end

  # POST /manage/settings/business/refresh_stripe
  def refresh_stripe
    if StripeService.check_onboarding_status(@business)
      flash[:notice] = 'Stripe onboarding complete!'
    else
      flash[:alert] = 'Stripe onboarding not yet completed.'
    end
    redirect_to edit_business_manager_settings_business_path
  end

  # DELETE /manage/settings/business/disconnect_stripe
  def disconnect_stripe
    if @business.update(stripe_account_id: nil)
      flash[:notice] = 'Stripe account disconnected.'
    else
      flash[:alert] = 'Failed to disconnect Stripe account.'
    end
    redirect_to edit_business_manager_settings_business_path
  end

  def edit
    # @business is set by set_business
    # The view will use @business to populate the form
  end

  def update
    # NOTE: The redirect path helper might need to change if it was based on the old controller name/module.
    # edit_settings_business_path should still work due to how routes are defined.
    
    # Log the sync_location parameter to help diagnose issues
    Rails.logger.info "[BUSINESS_SETTINGS] sync_location parameter: #{params[:sync_location].inspect}"
    
    if @business.update(business_params)
      # After update, check if hostname or subdomain changed
      if (@business.saved_change_to_hostname? || @business.saved_change_to_subdomain?)
        target_url = TenantHost.url_for(@business, request, edit_business_manager_settings_business_path)
        return redirect_to target_url, allow_other_host: true
      end
      # Check if the sync_location parameter is present with a value of '1'
      if params[:sync_location] == '1'
        sync_with_default_location
        redirect_to edit_business_manager_settings_business_path, notice: 'Business information updated.'
      else
        redirect_to edit_business_manager_settings_business_path, notice: 'Business information updated successfully.'
      end
    else
      render :edit, status: :unprocessable_content
    end
  end

  # POST /manage/settings/business/check_subdomain_availability
  def check_subdomain_availability
    result = SubdomainAvailabilityService.call(params[:subdomain], exclude_business: @business)
    render json: result.to_h
  end

  private

  def set_business
    # Use the current_business method from the base controller
    @business = current_business
    raise ActiveRecord::RecordNotFound unless @business
  end

  def authorize_business_settings
    # The policy class is explicitly Settings::BusinessPolicy.
    # If you want this to be BusinessManager::Settings::BusinessPolicy,
    # the policy file would also need to be moved/renamed and its class definition updated.
    # For now, leaving as is, assuming Settings::BusinessPolicy is correctly located and defined.
    authorize @business, :update_settings?, policy_class: Settings::BusinessPolicy
  end

  def business_params
    # Permit base attributes
    # NOTE: google_place_id is NOT permitted here - it must be set via the verified integrations flow
    # in IntegrationsController to ensure proper verification through GoogleBusinessVerificationService
    permitted = params.require(:business).permit(
      :name, :industry, :phone, :email, :website, :address, :city, :state, :zip, :description, :time_zone, :logo, :stock_management_enabled,
      :subdomain, :hostname, :host_type, :custom_domain_owned,
      # Permit individual hour fields, which will be processed into a JSON hash
      *days_of_week.flat_map { |day| ["hours_#{day}_open", "hours_#{day}_close"] }
    )

    # Process hours into a JSON structure
    hours_data = {}
    days_of_week.each do |day|
      open_key = "hours_#{day}_open"
      close_key = "hours_#{day}_close"

      open_time = permitted.delete(open_key)
      close_time = permitted.delete(close_key)

      # Store if either open or close time is present for the day
      if open_time.present? || close_time.present?
        hours_data[day.to_sym] = { open: open_time.presence, close: close_time.presence }
      end
    end

    # Assign the structured hours_data to the :hours attribute if it contains any day entries
    permitted[:hours] = hours_data if hours_data.any?

    permitted
  end

  def days_of_week
    %w[mon tue wed thu fri sat sun]
  end
  
  # Sync business data with the default location
  def sync_with_default_location
    default_location = @business.default_location
    
    if default_location.present?
      # Process hours data to ensure it's in the correct format
      hours_data = @business.hours
      if hours_data.is_a?(String)
        begin
          hours_data = JSON.parse(hours_data)
        rescue JSON::ParserError => e
          Rails.logger.error "[BUSINESS_SETTINGS] Error parsing hours JSON: #{e.message}"
        end
      end
      
      # Update the default location with the business address and hours
      default_location.update(
        address: @business.address,
        city: @business.city,
        state: @business.state,
        zip: @business.zip,
        hours: hours_data
      )
      
      Rails.logger.info "[BUSINESS_SETTINGS] Synced business info to default location ##{default_location.id}"
    else
      # Create a default location if one doesn't exist
      new_location = @business.locations.create!(
        name: "Main Location",
        address: @business.address,
        city: @business.city,
        state: @business.state,
        zip: @business.zip,
        hours: @business.hours || {}
      )
      
      Rails.logger.info "[BUSINESS_SETTINGS] Created new default location ##{new_location.id} for business ##{@business.id}"
    end
  end
end 