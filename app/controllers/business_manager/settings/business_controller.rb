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
      # If the user switched back to subdomain mode, run the same removal
      # service used by ActiveAdmin to clean up Render and revert safely.
      if @business.saved_change_to_host_type? && @business.host_type_subdomain?
        Rails.logger.info "[BUSINESS_SETTINGS] Host type switched to subdomain – invoking DomainRemovalService"
        begin
          removal_service = DomainRemovalService.new(@business)
          result = removal_service.remove_domain!
          if result[:success]
            flash[:notice] = 'Custom domain removed and reverted to subdomain.'
          else
            flash[:alert] = "Failed to remove custom domain: #{result[:error]}"
          end
        rescue => e
          Rails.logger.error "[BUSINESS_SETTINGS] Domain removal failed: #{e.message}"
          flash[:alert] = 'Failed to remove custom domain. Please try again or contact support.'
        end
      end

      # After update, check if hostname or subdomain changed
      if (@business.saved_change_to_hostname? || @business.saved_change_to_subdomain?)
        # Only redirect to custom domain if it's already active and working
        # For new custom domains, stay on current domain until setup is complete
        if @business.host_type_custom_domain? && !@business.custom_domain_allow?
          Rails.logger.info "[BUSINESS_SETTINGS] Custom domain #{@business.hostname} not yet active, staying on current domain"
          # Don't redirect - let user stay on current working domain
          flash[:notice] = "Custom domain configuration started! Check your email for setup instructions. You'll be able to use your custom domain once DNS is configured."
        else
          target_url = TenantHost.url_for(@business, request, edit_business_manager_settings_business_path)
          return redirect_to target_url, allow_other_host: true
        end
      end
      # Check if the sync_location parameter is present with a value of '1'
      # Preserve any flash set earlier (e.g., from DomainRemovalService) by only
      # providing a default notice when none exists.
      flash_already_set = flash[:alert].present? || flash[:notice].present?

      if params[:sync_location] == '1'
        sync_with_default_location
        if flash_already_set
          redirect_to edit_business_manager_settings_business_path
        else
          redirect_to edit_business_manager_settings_business_path, notice: 'Business information updated.'
        end
      else
        if flash_already_set
          redirect_to edit_business_manager_settings_business_path
        else
          redirect_to edit_business_manager_settings_business_path, notice: 'Business information updated successfully.'
        end
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

  # GET /manage/settings/business/check_domain_status
  def check_domain_status
    unless @business.host_type_custom_domain? && @business.hostname.present?
      return render json: { 
        error: 'Domain status checking is only available for custom domains' 
      }, status: :unprocessable_entity
    end

    begin
      # Initialize monitoring service (which includes all checkers)
      monitoring_service = DomainMonitoringService.new(@business)
      
      # Get comprehensive status
      # Use canonical domain for checking instead of raw hostname
      check_domain = @business.canonical_domain || @business.hostname
      dns_checker = CnameDnsChecker.new(check_domain)
      dual_verifier = DualDomainVerifier.new(@business.hostname) # Dual verifier needs raw hostname to check both apex/www
      health_checker = DomainHealthChecker.new(check_domain)
      render_service = RenderDomainService.new

      # Perform all checks
      dns_result = dns_checker.verify_cname
      dual_result = dual_verifier.verify_both_domains
      health_result = health_checker.check_health
      
      # Check render status
      render_result = begin
        domain = render_service.find_domain_by_name(check_domain)
        if domain
          verification = render_service.verify_domain(domain['id'])
          { found: true, verified: verification['verified'] == true }
        else
          { found: false, verified: false }
        end
      rescue => e
        { found: false, verified: false, error: e.message }
      end

      # Use verification strategy to determine status consistently
      verification_strategy = DomainVerificationStrategy.new(@business)
      verification_result = verification_strategy.determine_status(dns_result, render_result, health_result)
      
      overall_status = verification_result[:verified]
      status_message = if overall_status
        verification_result[:status_reason]
      elsif @business.status == 'cname_active' && @business.domain_health_verified
        'Domain is active and verified'
      else
        verification_result[:status_reason]
      end

      render json: {
        overall_status: overall_status,
        status_message: status_message,
        dns_check: {
          verified: dns_result[:verified],
          target: dns_result[:target],
          expected_target: dns_result[:expected_target],
          error: dns_result[:error]
        },
        dual_verification: {
          overall_verified: dual_result[:overall_verified],
          apex_domain: dual_result[:apex_domain],
          www_domain: dual_result[:www_domain]
        },
        render_check: {
          verified: render_result[:verified],
          found: render_result[:found],
          error: render_result[:error]
        },
        health_check: {
          healthy: health_result[:healthy],
          status_code: health_result[:status_code],
          response_time: health_result[:response_time],
          error: health_result[:error]
        },
        business_status: {
          status: @business.status,
          domain_health_verified: @business.domain_health_verified,
          render_domain_added: @business.render_domain_added,
          custom_domain_allow: @business.custom_domain_allow?
        }
      }

    rescue => e
      Rails.logger.error "[DomainStatusCheck] Error checking domain #{@business.hostname}: #{e.message}"
      error_response = { 
        error: 'Unable to check domain status'
      }
      
      # Only include error details in development/test environments
      if Rails.env.development? || Rails.env.test?
        error_response[:details] = e.message
      end
      
      render json: error_response, status: :internal_server_error
    end
  end

  # POST /manage/settings/business/finalize_domain_activation
  # Idempotent endpoint to persist activation immediately once checks pass.
  # Does not send emails and keeps GET semantics clean.
  def finalize_domain_activation
    unless @business.host_type_custom_domain? && @business.hostname.present?
      return render json: { error: 'Activation only applies to custom domains' }, status: :unprocessable_entity
    end

    begin
      check_domain = @business.canonical_domain || @business.hostname
      dns_checker = CnameDnsChecker.new(check_domain)
      dual_verifier = DualDomainVerifier.new(@business.hostname)
      health_checker = DomainHealthChecker.new(check_domain)
      render_service = RenderDomainService.new

      dns_result = dns_checker.verify_cname
      dual_result = dual_verifier.verify_both_domains
      health_result = health_checker.check_health

      render_result = begin
        domain = render_service.find_domain_by_name(check_domain)
        if domain
          verification = render_service.verify_domain(domain['id'])
          { found: true, verified: verification['verified'] == true }
        else
          { found: false, verified: false }
        end
      rescue => e
        { found: false, verified: false, error: e.message }
      end

      verification_strategy = DomainVerificationStrategy.new(@business)
      verification_result = verification_strategy.determine_status(dns_result, render_result, health_result)

      unless verification_result[:verified]
        return render json: {
          activated: false,
          status_message: verification_result[:status_reason]
        }, status: :unprocessable_entity
      end

      # Persist activation idempotently (no emails here)
      ActiveRecord::Base.transaction do
        @business.mark_domain_health_status!(true)
        @business.cname_success! unless @business.cname_active?
      end

      render json: {
        activated: true,
        business_status: {
          status: @business.status,
          domain_health_verified: @business.domain_health_verified,
          render_domain_added: @business.render_domain_added,
          custom_domain_allow: @business.custom_domain_allow?
        }
      }
    rescue => e
      Rails.logger.error "[DomainActivation] Failed to finalize activation for #{@business.hostname}: #{e.message}"
      render json: { error: 'Unable to finalize activation' }, status: :internal_server_error
    end
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
      :subdomain, :hostname, :host_type, :custom_domain_owned, :canonical_preference,
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