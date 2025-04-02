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
  before_action :authenticate_user!, unless: :maintenance_mode?

  # Error handling for tenant not found
  rescue_from ActsAsTenant::Errors::NoTenantSet, with: :tenant_not_found

  # Allow manually setting tenant in tests
  def self.allow_tenant_params
    # Used for testing - permits manually setting tenant in Devise controllers
    before_action :set_tenant_from_params, if: -> { Rails.env.test? && params[:tenant_id].present? }
  end

  private

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

  def companies_table_exists?
    ActiveRecord::Base.connection.table_exists?('companies')
  end

  def find_and_set_company_tenant(subdomain)
    company = Company.find_by(subdomain: subdomain)

    if company
      set_current_tenant(company)
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
