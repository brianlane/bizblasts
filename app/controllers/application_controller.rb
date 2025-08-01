# frozen_string_literal: true

# Main controller for the application that handles tenant setup, authentication,
# and error handling. Provides methods for maintenance mode and database connectivity checks.
class ApplicationController < ActionController::Base
  include Pundit::Authorization
  include DatabaseErrorHandling
  include PolicyEnforcement
  
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Handle CSRF token issues for admin login after user logout
  before_action :handle_admin_csrf_token, if: -> { request.path == '/admin/login' && request.post? }

  # Redirect admin access attempts from subdomains to the main domain
  before_action :redirect_admin_from_subdomain
  
  # Handle CSRF token issues for admin actions when crossing domains (non-test environments only)
  before_action :handle_admin_csrf_for_actions, if: -> { 
    !Rails.env.test? && 
    request.path.start_with?('/admin') && 
    !request.get? && 
    request.path != '/admin/login' 
  }

  # Set current tenant based on subdomain/custom domain
  # This filter should be skipped in specific controllers where tenant context is handled differently
  before_action :set_tenant, unless: -> { maintenance_mode? }
  before_action :check_database_connection

  # Authentication (now runs after tenant is set)
  before_action :authenticate_user!, unless: :skip_user_authentication?

  # Error handling for tenant not found
  rescue_from ActsAsTenant::Errors::NoTenantSet, with: :tenant_not_found

  # Handle Pundit NotAuthorizedError
  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  # Allow manually setting tenant in tests
  def self.allow_tenant_params
    # Used for testing - permits manually setting tenant in Devise controllers
    before_action :set_tenant_from_params, if: -> { Rails.env.test? && params[:tenant_id].present? }
  end

  # Authentication for ActiveAdmin - allows both AdminUser and User with admin role
  def authenticate_admin_user!
    # First try standard AdminUser authentication
    if admin_user_signed_in?
      return true
    end
    
    # Removed fallback to User with admin role
    
    # Otherwise redirect to login - use ActiveAdmin's login path if available
    redirect_to new_admin_user_session_path
  end

  # Helper method to check if admin user is signed in
  def admin_user_signed_in?
    warden.authenticated?(:admin_user)
  end

  # Helper method to get current admin user
  def current_admin_user
    # Removed fallback to User with admin role
    @current_admin_user ||= warden.authenticate(scope: :admin_user) if admin_user_signed_in?
  end

  # Fallback for serving ActiveAdmin assets directly if they're missing from the asset pipeline
  def self.serve_admin_assets
    Rails.application.routes.draw do
      # Direct file serving for admin assets as a last resort
      get '/assets/active_admin.css', to: proc { |env|
        file_path = Rails.root.join('public', 'assets', 'active_admin.css')
        if File.exist?(file_path)
          [200, {"Content-Type" => "text/css"}, [File.read(file_path)]]
        else
          [404, {"Content-Type" => "text/plain"}, ["Admin assets not found"]]
        end
      }, constraints: lambda { |req| req.format == :css }
    end
  end
  
  # Call the method to set up routes
  serve_admin_assets

  # Expose current tenant to controllers and views
  helper_method :current_tenant

  # Return the current ActsAsTenant tenant
  def current_tenant
    ActsAsTenant.current_tenant
  end

  # Make tenant setting logic protected so subclasses can call it
  protected 

  # Enhanced tenant setting method that handles both subdomains and custom domains
  # This method now uses ActsAsTenant for consistent tenant handling
  def set_tenant
    # Don't override if tenant is already set
    return if ActsAsTenant.current_tenant.present?
    
    # Check if this is a main domain request (should not have tenant)
    if main_domain_request?
      Rails.logger.debug "[SetTenant] Main domain request detected, skipping tenant setup"
      ActsAsTenant.current_tenant = nil
      return
    end
    
    # Try to find business by custom domain first
    business = find_business_by_custom_domain
    
    # If no custom domain match, try subdomain
    if business.nil?
      hostname = extract_hostname_for_tenant
      business = find_business_by_subdomain(hostname) if hostname.present?
    end
    
    # Set the tenant using ActsAsTenant if found
    if business
      ActsAsTenant.current_tenant = business
      Rails.logger.info "[SetTenant] Tenant set: Business ID #{business.id}"
      return
    end
    
    # Handle case where hostname/domain provided but no business found
    # Only show tenant_not_found if this looks like a subdomain request
    subdomain = request.subdomain
    
    if subdomain.present? && subdomain != 'www' && !main_domain_request?
      Rails.logger.warn "Tenant not found for hostname: #{subdomain}"
      tenant_not_found and return
    end
    
    # Session fallback logic for users who just signed up
    if user_signed_in? && session[:signed_up_business_id].present?
      fallback_business = Business.find_by(id: session[:signed_up_business_id])
      if fallback_business
        Business.set_current_tenant(fallback_business) # Use the Business model's method
        Rails.logger.info "Tenant set from session fallback: Business ID #{fallback_business.id}"
        # Consider clearing session after successful tenant switch
      else
        clear_tenant_and_log("Session fallback business ID not found: #{session[:signed_up_business_id]}")
        session.delete(:signed_up_business_id)
      end
      return
    end
    
    # Default case: No tenant context found
    clear_tenant_and_log("No specific tenant context found, clearing tenant.")
    ActsAsTenant.current_tenant = nil
  end

  # Helper to clear tenant and log - now uses ActsAsTenant
  def clear_tenant_and_log(message)
    Rails.logger.warn(message)
    ActsAsTenant.current_tenant = nil
  end

  # Check if businesses table exists (for handling migration scenarios)
  def businesses_table_exists?
    ActiveRecord::Base.connection.table_exists?('businesses')
  end

  # Find business by custom domain (exact hostname match)
  def find_business_by_custom_domain
    return nil unless businesses_table_exists?
    Business.find_by(host_type: 'custom_domain', hostname: request.host)
  end

  # Extract hostname/subdomain for tenant lookup
  def extract_hostname_for_tenant
    if Rails.env.development? || Rails.env.test?
      # Development: Use Rails' subdomain helper for lvh.me
      request.subdomain
    else
      # Production: Extract subdomain from bizblasts.com requests
      host_parts = request.host.split('.')
      
      # Handle standard bizblasts.com domains
      if host_parts.length >= 3 && host_parts.last(2).join('.') == 'bizblasts.com'
        first_part = host_parts.first
        return first_part unless first_part == 'www'
      end
      
      # Handle hosting platform scenarios (Render, Netlify, etc.)
      # Don't extract hostname from main domain patterns
      return nil if main_domain_request?
      
      # For custom domains or other scenarios, use the subdomain
      subdomain = request.subdomain
      return subdomain if subdomain.present? && subdomain != 'www'
      
      nil
    end
  end

  # Find business by subdomain
  def find_business_by_subdomain(hostname)
    return nil unless hostname.present? && businesses_table_exists?
    # Search for tenant businesses matching either hostname or subdomain (case-insensitive)
    Business.where(host_type: 'subdomain')
            .where("LOWER(hostname) = ? OR LOWER(subdomain) = ?", hostname.downcase, hostname.downcase)
            .first
  end

  # Legacy method - kept for compatibility but now uses ActsAsTenant directly
  def find_and_set_business_tenant(hostname)
    tenant = Business.find_by(hostname: hostname) || Business.find_by(subdomain: hostname)
    if tenant
      Business.set_current_tenant(tenant) # Use the Business model's method
      true
    else
      false
    end
  end

  def tenant_not_found
    @subdomain = request.subdomain || request.host
    render template: "errors/tenant_not_found", status: :not_found, layout: false
    false # Halt the filter chain
  end

  def set_tenant_from_params
    business = Business.find_by(id: params[:tenant_id])
    Business.set_current_tenant(business) if business
  end

  # Pundit authorization failure handler
  def user_not_authorized
    # Log security event for unauthorized access attempts
    SecureLogger.security_event('unauthorized_access', {
      user_id: current_user&.id,
      ip: request.remote_ip,
      path: request.fullpath,
      method: request.method
    })
    
    flash[:alert] = "You are not authorized to access this area."
    
    # For clients, redirect to their dashboard
    if user_signed_in? && current_user.client?
      redirect_to dashboard_path and return
    end
    
    # Otherwise redirect to root path
    redirect_to root_path, allow_other_host: true and return
  end


  # === DEVISE OVERRIDES ===
  # Customize the redirect path after sign-in
  # This method now properly handles both subdomain and custom domain scenarios
  def after_sign_in_path_for(resource)
    # Check the type of resource signed in (User, AdminUser, etc.)
    if resource.is_a?(AdminUser)
      admin_root_path
    elsif resource.is_a?(User)
      case resource.role
      when 'manager', 'staff'
        # Redirect manager/staff to their business-specific dashboard
        # This logic handles both subdomain and custom domain cases
        if resource.business.present?
          redirect_url = generate_business_dashboard_url(resource.business)
          Rails.logger.debug "[after_sign_in] Manager/Staff redirecting to business dashboard"
          redirect_url
        else
          # Fallback if user has no business (should not happen for manager/staff)
          Rails.logger.warn "[after_sign_in] Manager/Staff user ##{resource.id} has no associated business."
          root_path
        end
      when 'client'
        # Redirect clients to the main client dashboard (on the main domain)
        dashboard_path
      else
        # Fallback for unknown roles
        root_path 
      end
    else
      # Default fallback for other resource types
      super
    end
  end


  # Generate the correct dashboard URL for a business (subdomain or custom domain)
  def generate_business_dashboard_url(business, path = '/manage/dashboard')
    # Use TenantHost for all URL generation - it handles all environments and edge cases
    TenantHost.url_for(business, request, path)
  end

  # Keep other methods private
  private

  def skip_user_authentication?
    devise_controller? || request.path.start_with?('/admin') || maintenance_mode?
  end

  def maintenance_mode?
    # Use this to whitelist certain paths during database issues
    maintenance_paths.include?(request.path)
  end

  def maintenance_paths
    ['/healthcheck', '/up', '/maintenance', '/db-check']
  end

  def check_database_connection
    # Skip in test/development environment or if path is whitelisted
    return if maintenance_mode? || Rails.env.test? || Rails.env.development?
    
    begin
      # Attempt a lightweight database query
      ActiveRecord::Base.connection.execute("SELECT 1")
    rescue ActiveRecord::ConnectionNotEstablished
      database_connection_error
    end
  end

  # Redirects requests to /admin from a subdomain to the main domain
  # Now handles both subdomain and custom domain scenarios
  def redirect_admin_from_subdomain
    # Check if it's an admin path and not on the main domain
    if request.path.start_with?('/admin')
      # Skip if already on main domain
      return if main_domain_request?
      
      # Construct the main domain URL
      main_domain_url = construct_main_domain_url
      
      Rails.logger.info "[Redirect Admin] Redirecting admin access to main domain"
      redirect_to main_domain_url, status: :moved_permanently, allow_other_host: true
    end
  end
  
  # Check if the current request is on the main domain
  def main_domain_request?
    if Rails.env.development? || Rails.env.test?
      # Development/Test: Handle both lvh.me and example.com domains
      host = request.host.downcase
      main_domain_patterns = [
        'lvh.me',           # Development main domain
        'www.lvh.me',       # Development main domain with www
        'example.com',      # Test main domain
        'www.example.com'   # Test main domain with www (default in RSpec)
      ]
      return true if main_domain_patterns.include?(host)
      
      # Also check for no subdomain or www subdomain on these domains
      host_parts = request.host.split('.')
      if host_parts.length >= 2
        base_domain = host_parts.last(2).join('.')
        if ['lvh.me', 'example.com'].include?(base_domain)
          # Only main domain if no subdomain or www subdomain
          return host_parts.length == 2 || (host_parts.length == 3 && host_parts.first == 'www')
        end
      end
      
      false
    else
      # Production: Check for actual main domain patterns
      host = request.host.downcase
      
      # Direct main domain patterns
      main_domain_patterns = [
        'bizblasts.com',
        'www.bizblasts.com',
        'bizblasts.onrender.com'  # Render's internal routing
      ]
      
      return true if main_domain_patterns.include?(host)
      
      # For bizblasts.com, only treat www or no subdomain as main domain
      host_parts = request.host.split('.')
      if host_parts.length >= 2 && host_parts.last(2).join('.') == 'bizblasts.com'
        # Only main domain if no subdomain or www subdomain
        return host_parts.length == 2 || (host_parts.length == 3 && host_parts.first == 'www')
      end
      
      false
    end
  end
  
  # Construct URL for the main domain preserving the current path
  def construct_main_domain_url
    if Rails.env.development? || Rails.env.test?
      main_domain_host = 'lvh.me'
    else
      main_domain_host = 'bizblasts.com'
    end
    
    port = request.port unless [80, 443].include?(request.port)
    port_str = port ? ":#{port}" : ""
    "#{request.protocol}#{main_domain_host}#{port_str}#{request.fullpath}"
  end

  # Handle CSRF token issues when logging into admin after user logout
  def handle_admin_csrf_token
    # Check if this is an admin login attempt with invalid CSRF token
    if params[:admin_user].present? && !verified_request?
      Rails.logger.warn "[CSRF Fix] Admin login attempt with invalid CSRF token, allowing request"
      # Skip CSRF verification for this request by regenerating the token
      session[:_csrf_token] = nil
      form_authenticity_token
    end
  end

  # Handle CSRF token issues for admin actions when crossing domains (production only)
  def handle_admin_csrf_for_actions
    # Check if this is an admin action with invalid CSRF token
    if !verified_request?
      Rails.logger.warn "[CSRF Fix] Admin action with invalid CSRF token: #{request.method} #{request.path}"
      Rails.logger.warn "[CSRF Fix] User Agent: #{request.user_agent&.truncate(50)}"
      Rails.logger.warn "[CSRF Fix] Referer: [REDACTED]"
      
      # Instead of silently fixing it, redirect to the admin dashboard to get a fresh session
      # This is safer than bypassing CSRF for all admin actions
      flash[:alert] = "Session expired. Please try your action again."
      redirect_to admin_root_path and return
    end
  end

  # Ensure all times are in the current tenant's local time zone
  around_action :use_business_time_zone

  # Wrap request in the tenant's time zone
  def use_business_time_zone(&block)
    # Ensure business has a valid time_zone populated
    if ActsAsTenant.current_tenant&.respond_to?(:ensure_time_zone!)
      ActsAsTenant.current_tenant.ensure_time_zone!
    end
    tz = ActsAsTenant.current_tenant&.time_zone.presence || 'UTC'
    Time.use_zone(tz, &block)
  end
end