class Users::MagicLinksController < Devise::Passwordless::SessionsController
  # Override the show method to allow cross-host redirects
  def show
    resource_params = params.fetch(resource_name, {})
    email = resource_params[:email]
    token = resource_params[:token]
    redirect_param = resource_params[:redirect_to]
    self.resource = resource_class.find_by(email: email)
    
    # Validate the token using GlobalID approach like devise-passwordless does
    begin
      token_resource = GlobalID::Locator.locate_signed(token, for: 'login')
      token_valid = token_resource == resource
    rescue => e
      token_valid = false
    end
    
    if resource && token_valid
      # Sign in the user
      sign_in(resource_name, resource)
      # Rotate session token for extra security and set in session
      resource.rotate_session_token!
      session[:session_token] = resource.session_token

      # Set the success flash message like standard Devise does
      set_flash_message!(:notice, :signed_in)
      
      # Get the redirect path from params
      # Validate and sanitize the redirect path for security
      safe_redirect_path = safe_redirect_path(redirect_param)
      
      # Special handling for business users who need to be redirected to their subdomain
      if safe_redirect_path.present? && safe_redirect_path != '/' && (resource.manager? || resource.staff?) && resource.business.present?
        business_url = generate_business_dashboard_url(resource.business, safe_redirect_path)
        redirect_to business_url, allow_other_host: true
      elsif safe_redirect_path.present? && safe_redirect_path != '/'
        # For client users or other cases, use the redirect_path directly
        redirect_to safe_redirect_path, allow_other_host: true
      else
        # Fall back to the default after_sign_in_path which handles business user redirects
        redirect_to after_sign_in_path_for(resource), allow_other_host: true
      end
    else
      # Invalid token, redirect to sign in
      redirect_to new_user_session_path, alert: 'Invalid or expired magic link.'
    end
  end

  private

  # Validate and sanitize redirect paths to prevent open redirect attacks
  def safe_redirect_path(redirect_path)
    return nil unless redirect_path.present?
    
    # Only allow relative paths that start with /
    # This prevents redirects to external domains
    return nil unless redirect_path.start_with?('/')
    
    # Whitelist of allowed path patterns for additional security
    allowed_paths = [
      %r{\A/\z},                                    # Root path
      %r{\A/dashboard\z},                           # Dashboard
      %r{\A/settings/edit\z},                       # Client settings edit
      %r{\A/client/settings\z},                     # Client settings (legacy)
      %r{\A/manage/settings/profile/edit\z},        # Business settings profile
      %r{\A/manage/dashboard\z},                    # Business dashboard
      %r{\A/manage/settings\z},                     # Business settings
      %r{\A/manage/settings/business/edit\z},       # Business info settings page
      %r{\A/manage/settings/business/stripe_onboarding\z} # Stripe onboarding flow
    ]
    
    # Check if the path matches any allowed pattern
    return redirect_path if allowed_paths.any? { |pattern| redirect_path.match?(pattern) }
    
    # If path doesn't match whitelist, return nil for fallback behavior
    nil
  end

  # Generate a tenant-aware URL using the central helper
  def generate_business_dashboard_url(business, path = '/manage/dashboard')
    TenantHost.url_for(business, request, path)
  end
end
