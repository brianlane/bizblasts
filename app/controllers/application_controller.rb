# frozen_string_literal: true

# Main controller for the application that handles tenant setup, authentication,
# and error handling. Provides methods for maintenance mode and database connectivity checks.
class ApplicationController < ActionController::Base
  include Pundit::Authorization
  include DatabaseErrorHandling
  
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Set current tenant based on subdomain
  # set_current_tenant_through_filter # Removed - Relying solely on custom :set_tenant filter
  # Ensure set_tenant runs for the debug page to correctly identify tenant context
  before_action :set_tenant, unless: -> { maintenance_mode? }
  before_action :check_database_connection

  # Authentication (after tenant is set)
  before_action :authenticate_user!, unless: :skip_user_authentication?

  # Error handling for tenant not found
  rescue_from ActsAsTenant::Errors::NoTenantSet, with: :tenant_not_found

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

  def set_tenant
    hostname = request.subdomain.presence

    # If a specific hostname is present (and not www)
    if hostname.present? && hostname != "www"
      # Check table exists first to avoid errors
      unless businesses_table_exists?
        Rails.logger.error("Businesses table does not exist - skipping tenant setup for hostname: #{hostname}")
        # Decide how to handle this - clear tenant and proceed, or show an error?
        # For now, let's clear and proceed to avoid blocking non-tenant pages.
        clear_tenant_and_log("Businesses table missing, clearing tenant.")
        return
      end
      
      # Attempt to find and set the tenant by hostname
      if find_and_set_business_tenant(hostname)
        Rails.logger.info "Tenant set from hostname: #{hostname}"
        return # Tenant found and set, done.
      else
        # Hostname provided but no matching tenant found
        Rails.logger.warn "Tenant not found for hostname: #{hostname}"
        tenant_not_found # Render the specific error page
        return # Stop further processing
      end
    end

    # --- No specific hostname or it was 'www' ---

    # Session fallback logic (unchanged)
    if user_signed_in? && session[:signed_up_business_id].present?
      business = Business.find_by(id: session[:signed_up_business_id])
      if business
        set_current_tenant(business)
        Rails.logger.info "Tenant set from session fallback: Business ##{business.id}"
        # Consider clearing session.delete(:signed_up_business_id)
      else
        clear_tenant_and_log("Session fallback business ID not found: #{session[:signed_up_business_id]}")
        session.delete(:signed_up_business_id)
      end
      return # Tenant set (or cleared) based on session
    end

    # Default case: No specific tenant context found (no valid hostname, no session fallback)
    clear_tenant_and_log("No specific tenant context found, clearing tenant.")
    # ActsAsTenant.current_tenant is already nil here

    if user_signed_in?
      case current_user.role
      when 'manager'
        ActsAsTenant.current_tenant = current_user.business
      when 'client'
        ActsAsTenant.current_tenant = nil
      when 'admin'
        return # Skip tenant setup for admins
      end
    end
  end

  # Helper to clear tenant and log
  def clear_tenant_and_log(message)
    Rails.logger.warn(message)
    ActsAsTenant.current_tenant = nil
  end

  protected

  def businesses_table_exists?
    # Check if either businesses table exists
    ActiveRecord::Base.connection.table_exists?('businesses')
  end

  def find_and_set_business_tenant(hostname)
    tenant = Business.find_by(hostname: hostname)
    if tenant
      Business.set_current_tenant(tenant)
      true
    else
      false
    end
  end

  def tenant_not_found
    @subdomain = request.subdomain
    render template: "errors/tenant_not_found", status: :not_found
  end

  def set_tenant_from_params
    business = Business.find_by(id: params[:tenant_id])
    Business.set_current_tenant(business) if business
  end
end
