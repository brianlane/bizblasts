# frozen_string_literal: true

module Users
  # Custom sessions controller to handle redirection after sign-in
  class SessionsController < Devise::SessionsController
    # skip_before_action :set_tenant, only: :destroy # REMOVED: Global filter was removed
    skip_before_action :verify_authenticity_token, only: :create, if: -> { request.format.json? }

    # For tests, we need to override the sign_in method
    def create
      # We can't rely on super because it doesn't handle cross-domain redirects properly
      self.resource = warden.authenticate!(auth_options)
      set_flash_message!(:notice, :signed_in)
      sign_in(resource_name, resource)
      
      # Store business ID in session if applicable (still useful for other potential logic)
      if resource.respond_to?(:business) && resource.business.present?
        session[:business_id] = resource.business.id
      end
      
      # Get the redirect path manually rather than using respond_with
      redirect_path = after_sign_in_path_for(resource)
      
      # Use redirect_to with allow_other_host: true to handle cross-domain redirects
      if redirect_path.include?("://") && redirect_path != request.url
        Rails.logger.debug "[Sessions::create] Redirecting to external URL: #{redirect_path}"
        redirect_to redirect_path, allow_other_host: true, status: :see_other
      else
        Rails.logger.debug "[Sessions::create] Redirecting to internal path: #{redirect_path}"
        redirect_to redirect_path, status: :see_other
      end
    end
    
    # Override the path users are redirected to after sign in
    def after_sign_in_path_for(resource)
      # Check if the user is a business user (manager or staff) and has an associated business
      if resource.is_a?(User) && resource.has_any_role?(:manager, :staff) && resource.business.present?
        Rails.logger.debug "[Sessions::after_sign_in] Business User: #{resource.email}. Redirecting to tenant dashboard."
        
        # Construct the URL for the tenant's dashboard
        host = "#{resource.business.hostname}.lvh.me"
        port = request.port unless [80, 443].include?(request.port)
        port_str = port ? ":#{port}" : ""
        url = "#{request.protocol}#{host}#{port_str}/dashboard"
        
        Rails.logger.debug "[Sessions::after_sign_in] Calculated redirect URL: #{url}"
        return url # Return the URL string, Devise will handle the actual redirect
      end
      
      # Default Devise behavior or other roles (like client)
      # Stored location has precedence
      stored_location = stored_location_for(resource)
      if stored_location
        Rails.logger.debug "[Sessions::after_sign_in] User: #{resource.email}. Redirecting to stored location: #{stored_location}."
        return stored_location
      end

      # Fallback to root path if no stored location
      Rails.logger.debug "[Sessions::after_sign_in] User: #{resource.email}. No stored location, redirecting to root_path."
      root_path
    end

    def destroy
      # Remember if we're on a subdomain
      @was_on_subdomain = request.subdomain.present? && request.subdomain != 'www'
      
      # Clear our custom cookies
      cookies.delete(:business_id, domain: '.lvh.me')
      
      super do
        # After sign out, redirect to the home page on the main domain
        if @was_on_subdomain
          # Get the main domain (without the subdomain)
          main_domain = "lvh.me"
          port = request.port unless [80, 443].include?(request.port)
          port_str = port ? ":#{port}" : ""
          url = "#{request.protocol}#{main_domain}#{port_str}/"
          
          Rails.logger.debug "[Sessions::destroy] Redirecting to main domain: #{url}"
          redirect_to url, allow_other_host: true and return
        else
          redirect_to root_path and return
        end
      end
    end
  end
end