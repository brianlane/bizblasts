# frozen_string_literal: true

# GoogleBusinessOauthController handles OAuth callbacks for Google Business Profile API
# This controller operates outside tenant constraints for security (similar to CalendarOauthController)
class GoogleBusinessOauthController < ApplicationController
  skip_before_action :authenticate_user!
  skip_before_action :set_tenant
  
  # GET /oauth/google-business/callback
  def callback
    code = params[:code]
    state = params[:state]
    error = params[:error]
    
    # Find the business and user from the state parameter stored in session
    business_id = session[:oauth_business_id]
    user_id = session[:oauth_user_id]
    expected_state = session[:oauth_state]
    
    if business_id.blank? || user_id.blank?
      Rails.logger.error "[GoogleBusinessOAuth] Missing business_id or user_id in session"
      redirect_to_error('OAuth session expired. Please try again.')
      return
    end
    
    # Verify state parameter
    if state != expected_state
      Rails.logger.error "[GoogleBusinessOAuth] State parameter mismatch"
      redirect_to_error('OAuth state mismatch. Please try again.')
      return
    end
    
    if error.present?
      Rails.logger.error "[GoogleBusinessOAuth] OAuth error: #{error}"
      redirect_to_error('OAuth authorization failed. Please try again.')
      return
    end
    
    if code.blank?
      Rails.logger.error "[GoogleBusinessOAuth] No authorization code received"
      redirect_to_error('No authorization code received. Please try again.')
      return
    end
    
    # Find business and user
    business = Business.find_by(id: business_id)
    user = User.find_by(id: user_id)
    
    unless business && user
      Rails.logger.error "[GoogleBusinessOAuth] Invalid business or user from session"
      redirect_to_error('Invalid session data. Please try again.')
      return
    end
    
    # Generate the callback URL that was used for this request
    callback_url = google_business_oauth_callback_url
    
    # Exchange code for tokens and fetch business profiles
    result = GoogleBusinessProfileService.exchange_code_and_fetch_profiles(code, callback_url)
    
    if result[:success]
      Rails.logger.info "[GoogleBusinessOAuth] Successfully fetched #{result[:accounts]&.length || 0} accounts for business #{business.id}"
      
      # Store accounts and tokens in session for the user to select from
      session[:google_business_accounts] = result[:accounts]
      session[:google_oauth_tokens] = result[:tokens]
      
      # Clear OAuth session data
      session.delete(:oauth_business_id)
      session.delete(:oauth_user_id)
      session.delete(:oauth_state)
      
      # Redirect back to the business integrations page with success
      redirect_to_business_integrations(business, user, 
        notice: 'Connected to Google! Please select your business account below.',
        show_google_accounts: true)
    else
      Rails.logger.error "[GoogleBusinessOAuth] Token exchange failed: #{result[:error]}"
      redirect_to_business_integrations(business, user,
        alert: result[:error] || 'Failed to connect to Google Business Profile.')
    end
  rescue => e
    Rails.logger.error "[GoogleBusinessOAuth] Callback error: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    
    # Try to redirect back to business if we have the data
    if business_id && user_id
      business = Business.find_by(id: business_id)
      user = User.find_by(id: user_id)
      redirect_to_business_integrations(business, user, 
        alert: 'OAuth process failed. Please try again.')
    else
      redirect_to_error('OAuth process failed. Please try again.')
    end
  end
  
  private
  
  def redirect_to_error(message)
    # Fallback redirect - go to root with error
    redirect_to root_path, alert: message
  end
  
  def redirect_to_business_integrations(business, user, options = {})
    return redirect_to_error(options[:alert] || 'Session error') unless business && user
    
    # Build the business integrations URL
    if business.host_type_custom_domain?
      host = business.hostname
      scheme = Rails.env.production? ? 'https' : 'http'
      port = Rails.env.development? ? ':3000' : ''
      base_url = "#{scheme}://#{host}#{port}"
    else
      # Use subdomain
      subdomain = business.subdomain || business.hostname
      if Rails.env.development?
        base_url = "http://#{subdomain}.lvh.me:3000"
      else
        base_url = "https://#{subdomain}.bizblasts.com"
      end
    end
    
    # Build query parameters
    query_params = {}
    query_params[:show_google_accounts] = true if options[:show_google_accounts]
    query_string = query_params.any? ? "?#{query_params.to_query}" : ""
    
    integrations_url = "#{base_url}/manage/settings/integrations#{query_string}"
    
    # For notices/alerts, we'll need to pass them via flash
    # Since this is a cross-domain redirect, we can't use normal flash
    # Instead, we'll add them as URL parameters
    if options[:notice]
      query_params[:oauth_notice] = options[:notice]
    elsif options[:alert]
      query_params[:oauth_alert] = options[:alert]
    end
    
    final_query_string = query_params.any? ? "?#{query_params.to_query}" : ""
    final_url = "#{base_url}/manage/settings/integrations#{final_query_string}"
    
    Rails.logger.info "[GoogleBusinessOAuth] Redirecting to: #{final_url}"
    redirect_to final_url, allow_other_host: true
  end
end