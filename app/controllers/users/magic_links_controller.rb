class Users::MagicLinksController < Devise::MagicLinksController
  # Override the show method to allow cross-host redirects
  def show
    self.resource = resource_class.find_by(email: params[resource_name][:email])
    
    # Validate the token using GlobalID approach like devise-passwordless does
    begin
      token_resource = GlobalID::Locator.locate_signed(params[resource_name][:token], for: 'login')
      token_valid = token_resource == resource
    rescue => e
      token_valid = false
    end
    
    if resource && token_valid
      # Sign in the user
      sign_in(resource_name, resource)
      
      # Set the success flash message like standard Devise does
      set_flash_message!(:notice, :signed_in)
      
      # Get the redirect path from params
      redirect_path = params[resource_name][:redirect_to]
      
      # Special handling for business users who need to be redirected to their subdomain
      if redirect_path.present? && redirect_path != '/' && (resource.manager? || resource.staff?) && resource.business.present?
        business_url = generate_business_dashboard_url(resource.business, redirect_path)
        redirect_to business_url, allow_other_host: true
      elsif redirect_path.present? && redirect_path != '/'
        # For client users or other cases, use the redirect_path directly
        redirect_to redirect_path, allow_other_host: true
      else
        # Fall back to the default after_sign_in_path which handles business user redirects
        redirect_to after_sign_in_path_for(resource), allow_other_host: true
      end
    else
      # Invalid token, redirect to sign in
      redirect_to new_user_session_path, alert: 'Invalid or expired magic link.'
    end
  end
end
