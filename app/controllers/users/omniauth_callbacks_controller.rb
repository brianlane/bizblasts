# frozen_string_literal: true

module Users
  # Handles OmniAuth callbacks for social authentication (Google, etc.)
  # This controller manages both sign-in and sign-up flows via OAuth providers.
  #
  # Flow:
  # 1. User clicks "Sign in/up with Google" on any domain
  # 2. Session stores the registration type and return URL
  # 3. User is redirected to Google's OAuth consent screen
  # 4. Google redirects back to this controller's callback action
  # 5. We create/find user and establish session
  # 6. If on tenant domain, we use auth bridge for cross-domain authentication
  class OmniauthCallbacksController < Devise::OmniauthCallbacksController
    # Skip tenant requirement for OAuth callbacks (they come from external providers)
    skip_before_action :set_tenant, raise: false

    # OmniAuth handles CSRF via state parameter. We limit CSRF skipping to non-GET HTML requests.
    skip_before_action :verify_authenticity_token,
                        only: [:google_oauth2, :failure],
                        if: -> { request.format&.html? && !request.get? }

    # Google OAuth2 callback
    # GET/POST /users/auth/google_oauth2/callback
    def google_oauth2
      handle_oauth_callback("Google")
    end

    # Handle OAuth failures
    def failure
      error_message = request.env["omniauth.error.type"]&.to_s&.humanize || "Unknown error"
      Rails.logger.warn "[OmniAuth] Authentication failure: #{error_message}"

      # Redirect back to stored return URL or sign-in page
      return_url = session.delete(:omniauth_return_url)
      registration_type = session.delete(:omniauth_registration_type)

      redirect_path = case registration_type
                      when "client"
                        new_client_registration_path
                      when "business"
                        new_business_registration_path
                      else
                        new_user_session_path
                      end

      redirect_to redirect_path, alert: "Authentication failed: #{error_message}. Please try again."
    end

    private

    # Generic handler for OAuth callbacks
    def handle_oauth_callback(provider_name)
      auth = request.env["omniauth.auth"]
      registration_type = session.delete(:omniauth_registration_type)
      return_url = session.delete(:omniauth_return_url)
      origin_host = session.delete(:omniauth_origin_host)
      business_id = session.delete(:omniauth_business_id)

      Rails.logger.info "[OmniAuth] Callback from #{provider_name}: email=#{auth.info.email}, registration_type=#{registration_type}"

      # Get user from OmniAuth data
      @user = User.from_omniauth(auth, current_user, registration_type)

      if @user.persisted?
        # Existing user (or newly linked OAuth account)
        handle_existing_user_sign_in(provider_name, return_url, origin_host, business_id)
      else
        # New user - need to complete registration
        handle_new_user_registration(provider_name, registration_type, return_url, origin_host)
      end
    end

    # Handle sign-in for existing users
    def handle_existing_user_sign_in(provider_name, return_url, origin_host, business_id)
      # Track successful OAuth login
      SecureLogger.info "[OmniAuth] Signed in existing user #{@user.id} via #{provider_name}"

      # Sign in the user
      sign_in_and_redirect_user(@user, return_url, origin_host, business_id)
    end

    # Handle registration for new users
    def handle_new_user_registration(provider_name, registration_type, return_url, origin_host)
      case registration_type
      when "business"
        # Business registration requires additional info - store OAuth data and redirect to form
        session[:omniauth_data] = {
          provider: @user.provider,
          uid: @user.uid,
          email: @user.email,
          first_name: @user.first_name,
          last_name: @user.last_name
        }
        flash[:notice] = "Please complete your business information to finish registration."
        redirect_to new_business_registration_path
      else
        # Client registration - save user directly
        @user.skip_confirmation_notification! # We'll send confirmation email
        
        if @user.save
          SecureLogger.info "[OmniAuth] Created new client user #{@user.id} via #{provider_name}"
          
          # Send confirmation email (OAuth users still need to confirm per requirements)
          @user.send_confirmation_instructions
          
          # Sign in the user (they can access some features before confirmation)
          sign_in_and_redirect_user(@user, return_url, origin_host, nil, new_registration: true)
        else
          Rails.logger.error "[OmniAuth] Failed to create user: #{@user.errors.full_messages.join(', ')}"
          session[:omniauth_data] = {
            provider: @user.provider,
            uid: @user.uid,
            email: @user.email,
            first_name: @user.first_name,
            last_name: @user.last_name
          }
          redirect_to new_client_registration_path, alert: "Could not complete registration: #{@user.errors.full_messages.first}"
        end
      end
    end

    # Sign in user and handle cross-domain redirect
    def sign_in_and_redirect_user(user, return_url, origin_host, business_id, new_registration: false)
      # Sign in the user
      sign_in(user)

      # Rotate session token for security
      user.rotate_session_token!
      session[:session_token] = user.session_token

      # Track session creation
      AuthenticationTracker.track_session_created(user, request)

      # Store business ID in session if applicable
      if user.respond_to?(:business) && user.business.present?
        session[:business_id] = user.business.id
      end

      # Set appropriate flash message
      if new_registration
        set_flash_message!(:notice, :signed_up) if is_navigational_format?
      else
        set_flash_message!(:notice, :signed_in) if is_navigational_format?
      end

      # Determine redirect URL
      redirect_url = determine_redirect_url(user, return_url, origin_host, business_id)

      # Check if we need to use auth bridge for cross-domain redirect
      if needs_auth_bridge?(redirect_url, origin_host)
        redirect_via_auth_bridge(redirect_url, business_id)
      else
        redirect_to redirect_url, allow_other_host: true
      end
    end

    # Determine the final redirect URL
    def determine_redirect_url(user, return_url, origin_host, business_id)
      # If there's a return URL from before OAuth, use it
      return return_url if return_url.present? && valid_return_url?(return_url)

      # Check for stored location (Devise standard)
      stored = stored_location_for(user)
      return stored if stored.present?

      # Determine based on user role
      if user.has_any_role?(:manager, :staff) && user.business.present?
        # Business users go to tenant dashboard
        TenantHost.url_for(user.business, request, '/manage/dashboard')
      elsif user.client?
        dashboard_path
      else
        root_path
      end
    end

    # Check if auth bridge is needed for cross-domain authentication
    def needs_auth_bridge?(redirect_url, origin_host)
      return false unless redirect_url.present?

      begin
        uri = URI.parse(redirect_url)
        return false unless uri.host.present?

        # Compare hosts (ignoring www prefix)
        current_host = request.host.downcase.sub(/^www\./, '')
        target_host = uri.host.downcase.sub(/^www\./, '')

        # Need bridge if redirecting to a different domain
        current_host != target_host
      rescue URI::InvalidURIError
        false
      end
    end

    # Redirect via auth bridge for cross-domain authentication
    def redirect_via_auth_bridge(target_url, business_id)
      begin
        # Find the business for this custom domain
        business = if business_id.present?
                     Business.find_by(id: business_id)
                   else
                     uri = URI.parse(target_url)
                     Business.find_by(hostname: uri.host) || Business.find_by(canonical_domain: uri.host)
                   end

        if business&.host_type_custom_domain?
          # Create auth token for cross-domain transfer
          auth_token = AuthToken.create_for_user!(current_user, target_url, request)

          # Build consumption URL
          uri = URI.parse(target_url)
          consumption_url = "#{uri.scheme}://#{uri.host}"
          consumption_url += ":#{uri.port}" if uri.port && ![80, 443].include?(uri.port)
          consumption_url += "/auth/consume?auth_token=#{CGI.escape(auth_token.token)}"

          # Preserve target path
          if uri.path.present? && uri.path != '/'
            consumption_url += "&redirect_to=#{CGI.escape(uri.path)}"
          end

          redirect_to consumption_url, allow_other_host: true
        else
          # No auth bridge needed - direct redirect
          redirect_to target_url, allow_other_host: true
        end
      rescue => e
        Rails.logger.error "[OmniAuth] Auth bridge error: #{e.message}"
        redirect_to root_path, alert: "Authentication successful, but there was an error redirecting. Please navigate manually."
      end
    end

    # Validate return URL to prevent open redirects
    def valid_return_url?(url)
      return false unless url.present?

      begin
        uri = URI.parse(url)

        # Allow relative URLs
        return true unless uri.host.present?

        # Check against allowed domains
        allowed_domains = if Rails.env.production?
                            ['bizblasts.com', 'www.bizblasts.com']
                          elsif Rails.env.development?
                            ['lvh.me', 'localhost']
                          else
                            ['example.com', 'test.host']
                          end

        # Also allow custom domains from businesses
        if uri.host.present?
          host = uri.host.downcase.sub(/^www\./, '')
          return true if allowed_domains.any? { |d| host == d || host.end_with?(".#{d}") }

          # Check if it's a registered business domain
          Business.where(host_type: 'custom_domain').exists?(hostname: host) ||
            Business.where(host_type: 'custom_domain').exists?(canonical_domain: host)
        end

        false
      rescue URI::InvalidURIError
        false
      end
    end
  end
end

