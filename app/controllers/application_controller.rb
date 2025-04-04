# frozen_string_literal: true

# Main controller for the application that handles tenant setup, authentication,
# and error handling. Provides methods for maintenance mode and database connectivity checks.
class ApplicationController < ActionController::Base
  include DatabaseErrorHandling
  
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Set current tenant based on subdomain
  set_current_tenant_through_filter
  before_action :set_tenant, unless: :maintenance_mode?
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
    
    # Fallback to User with admin role for tests
    if user_signed_in? && current_user.respond_to?(:role) && current_user.role == 'admin'
      return true
    end
    
    # Otherwise redirect to login - use ActiveAdmin's login path if available
    if request.path.start_with?('/admin')
      redirect_to new_admin_user_session_path
    else
      redirect_to new_user_session_path
    end
  end

  # Helper method to check if admin user is signed in
  def admin_user_signed_in?
    warden.authenticated?(:admin_user)
  end

  # Helper method to get current admin user
  def current_admin_user
    if admin_user_signed_in?
      @current_admin_user ||= warden.authenticate(scope: :admin_user)
    elsif user_signed_in? && current_user.respond_to?(:role) && current_user.role == 'admin'
      # Use the admin User for tests
      current_user
    end
  end

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
    return if maintenance_mode?
    
    begin
      # Attempt a lightweight database query
      ActiveRecord::Base.connection.execute("SELECT 1")
    rescue ActiveRecord::ConnectionNotEstablished
      database_connection_error
    end
  end

  def set_tenant
    subdomain = request.subdomain.presence

    # Skip for www or blank subdomains
    return if subdomain.blank? || subdomain == "www"

    nil unless table_exists_and_set_company(subdomain)
  end

  def table_exists_and_set_company(subdomain)
    # First check if the companies table exists to prevent errors
    unless companies_table_exists?
      Rails.logger.error("Companies table does not exist - skipping tenant setup")
      return false
    end

    find_and_set_company_tenant(subdomain)
  rescue => e
    # Log the error but continue with the request (default tenant)
    Rails.logger.error("Error setting tenant: #{e.message}")
    false
  end

  protected

  def companies_table_exists?
    # Check if either companies or businesses table exists
    ActiveRecord::Base.connection.table_exists?('companies') || 
    ActiveRecord::Base.connection.table_exists?('businesses')
  end

  def find_and_set_company_tenant(subdomain)
    # Try to find the tenant in either Company or Business tables
    tenant = nil
    
    if ActiveRecord::Base.connection.table_exists?('companies')
      tenant = Company.find_by(subdomain: subdomain)
    end
    
    # If not found in companies, try businesses
    if tenant.nil? && ActiveRecord::Base.connection.table_exists?('businesses')
      tenant = Business.find_by(subdomain: subdomain)
    end

    if tenant
      set_current_tenant(tenant)
      true
    else
      tenant_not_found
      false
    end
  end

  def tenant_not_found
    @subdomain = request.subdomain
    render template: "errors/tenant_not_found", status: :not_found
  end

  def set_tenant_from_params
    company = Company.find_by(id: params[:tenant_id])
    set_current_tenant(company) if company
  end
end
