# frozen_string_literal: true

# Main controller for the application that handles tenant setup, authentication,
# and error handling. Provides methods for maintenance mode and database connectivity checks.
class ApplicationController < ActionController::Base
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
  rescue_from ActiveRecord::ConnectionNotEstablished, with: :database_connection_error
  rescue_from PG::UndefinedTable, with: :handle_undefined_table
  rescue_from ActiveRecord::StatementInvalid, with: :handle_statement_invalid

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
    return unless table_exists_and_set_company(subdomain)
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

  def database_connection_error
    if maintenance_mode?
      handle_maintenance_health_check
    else
      render_database_error_response
    end
  end

  def handle_maintenance_health_check
    if request.path == '/healthcheck'
      render json: { status: 'ok', message: 'Health check passed, database not available' }, status: :ok
    else
      # For other maintenance paths, show a maintenance page
      render template: "errors/maintenance", status: :service_unavailable
    end
  end

  def render_database_error_response
    respond_to do |format|
      format.html { render template: "errors/maintenance", status: :service_unavailable }
      format.json { render json: { error: 'Database connection error' }, status: :service_unavailable }
    end
  end

  def handle_undefined_table(exception)
    Rails.logger.error("Database table error: #{exception.message}")
    
    # For API requests return JSON
    respond_to do |format|
      format.html { render template: "errors/maintenance", status: :service_unavailable }
      format.json { render json: { error: 'Database table error', details: exception.message }, status: :service_unavailable }
    end
  end

  def handle_statement_invalid(exception)
    Rails.logger.error("SQL Statement error: #{exception.message}")
    
    # Handle the specific "relation does not exist" error
    if exception.message.include?('relation "companies" does not exist')
      return attempt_to_fix_companies_table
    end
    
    # Fallback to maintenance mode
    render_statement_invalid_response(exception)
  end

  def attempt_to_fix_companies_table
    Rails.logger.info("Attempting to fix companies table")
    create_companies_table
    create_default_company
    redirect_to request.path
  rescue => e
    Rails.logger.error("Failed to fix companies table: #{e.message}")
    render_statement_invalid_response(e)
  end

  def create_companies_table
    ActiveRecord::Base.connection.create_table(:companies) do |t|
      t.string :name, null: false, default: 'Default'
      t.string :subdomain, null: false, default: 'default'
      t.timestamps
    end
  end

  def create_default_company
    Company.find_or_create_by!(name: 'Default Company', subdomain: 'default')
  end

  def render_statement_invalid_response(exception)
    respond_to do |format|
      format.html { render template: "errors/maintenance", status: :service_unavailable }
      format.json { render json: { error: 'Database error', details: exception.message }, status: :service_unavailable }
    end
  end
end
