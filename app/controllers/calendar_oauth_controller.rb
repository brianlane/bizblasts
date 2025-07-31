# frozen_string_literal: true

class CalendarOauthController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:callback]
  
  def callback
    provider = params[:provider]
    code = params[:code]
    state = params[:state]
    error = params[:error]
    
    # Handle OAuth errors
    if error.present?
      handle_oauth_error(error, params[:error_description])
      return
    end
    
    # Validate required parameters
    unless provider.present? && code.present? && state.present?
      redirect_to_error("Missing required OAuth parameters")
      return
    end
    
    # Process the OAuth callback
    oauth_handler = Calendar::OauthHandler.new
    redirect_uri = calendar_oauth_callback_url(provider)
    
    calendar_connection = oauth_handler.handle_callback(provider, code, state, redirect_uri)
    
    if calendar_connection
      handle_successful_connection(calendar_connection)
    else
      handle_failed_connection(oauth_handler.errors)
    end
  end
  
  private
  
  def handle_oauth_error(error, description = nil)
    Rails.logger.error("OAuth error: #{error} - #{description}")
    
    case error
    when 'access_denied'
      redirect_to_error("Calendar access was denied. Please try again if you want to connect your calendar.")
    when 'invalid_request'
      redirect_to_error("Invalid OAuth request. Please try again.")
    when 'unauthorized_client'
      redirect_to_error("Unauthorized calendar application. Please contact support.")
    when 'unsupported_response_type'
      redirect_to_error("Unsupported OAuth response type. Please contact support.")
    when 'invalid_scope'
      redirect_to_error("Invalid calendar permissions requested. Please contact support.")
    when 'server_error'
      redirect_to_error("Calendar service is temporarily unavailable. Please try again later.")
    when 'temporarily_unavailable'
      redirect_to_error("Calendar service is temporarily unavailable. Please try again later.")
    else
      redirect_to_error("Calendar connection failed: #{description || error}")
    end
  end
  
  def handle_successful_connection(calendar_connection)
    business = calendar_connection.business
    
    # Generate success message
    provider_name = calendar_connection.provider_display_name
    staff_name = calendar_connection.staff_member.name
    
    flash[:notice] = "Successfully connected #{provider_name} for #{staff_name}! Your bookings will now sync automatically."
    
    # Redirect to business subdomain calendar settings
    redirect_to_business_calendar_settings(business)
  end
  
  def handle_failed_connection(errors)
    error_messages = errors.full_messages.join('. ')
    Rails.logger.error("Calendar connection failed: #{error_messages}")
    
    # Try to redirect to the business if we can determine it from the state
    # Otherwise redirect to main domain with error
    redirect_to_error("Failed to connect calendar: #{error_messages}")
  end
  
  # Always send the user back to the host that handled the OAuth callback so
  # we do not unexpectedly switch between custom-domain and sub-domain URLs.
  def redirect_to_business_calendar_settings(_business)
    target_url = "#{request.protocol}#{request.host_with_port}/manage/settings/calendar_integrations"
    redirect_to target_url, allow_other_host: true
  end
  
  def redirect_to_error(message)
    # Try to redirect to a business subdomain if we can determine it
    # Otherwise redirect to main domain
    
    if params[:state].present?
      begin
        state_data = Rails.application.message_verifier(:calendar_oauth).verify(params[:state])
        business = Business.find(state_data['business_id'])
        
        if business.subdomain.present?
          redirect_to "#{request.protocol}#{business.subdomain}.#{request.domain}/manage/settings/calendar_integrations",
                     alert: message
          return
        end
      rescue => e
        Rails.logger.warn("Could not parse OAuth state for error redirect: #{e.message}")
      end
    end
    
    # Fallback to root with error
    redirect_to root_path, alert: message
  end
end