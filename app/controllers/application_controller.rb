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
    request.path == '/healthcheck' || 
    request.path == '/up' || 
    request.path == '/maintenance' ||
    request.path == '/db-check'
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

    begin
      # First check if the companies table exists to prevent errors
      unless ActiveRecord::Base.connection.table_exists?('companies')
        Rails.logger.error("Companies table does not exist - skipping tenant setup")
        return
      end

      # Find the company by subdomain
      company = Company.find_by(subdomain: subdomain)

      if company
        set_current_tenant(company)
      else
        tenant_not_found
      end
    rescue => e
      # Log the error but continue with the request (default tenant)
      Rails.logger.error("Error setting tenant: #{e.message}")
    end
  end

  def tenant_not_found
    @subdomain = request.subdomain
    render template: "errors/tenant_not_found", status: :not_found
  end

  def database_connection_error
    # Only return a success response for health checks
    if maintenance_mode?
      if request.path == '/healthcheck'
        render json: { status: 'ok', message: 'Health check passed, database not available' }, status: :ok
      else
        # For other maintenance paths, show a maintenance page
        render template: "errors/maintenance", status: :service_unavailable
      end
    else
      # For all other pages, return a 503 service unavailable
      respond_to do |format|
        format.html { render template: "errors/maintenance", status: :service_unavailable }
        format.json { render json: { error: 'Database connection error' }, status: :service_unavailable }
      end
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
      # Try to create the companies table on the fly
      begin
        Rails.logger.info("Attempting to fix companies table")
        ActiveRecord::Base.connection.create_table(:companies) do |t|
          t.string :name, null: false, default: 'Default'
          t.string :subdomain, null: false, default: 'default'
          t.timestamps
        end
        # Create a default company
        Company.find_or_create_by!(name: 'Default Company', subdomain: 'default')
        # Retry the original request by redirecting
        return redirect_to request.path
      rescue => e
        Rails.logger.error("Failed to fix companies table: #{e.message}")
      end
    end
    
    # Fallback to maintenance mode
    respond_to do |format|
      format.html { render template: "errors/maintenance", status: :service_unavailable }
      format.json { render json: { error: 'Database error', details: exception.message }, status: :service_unavailable }
    end
  end
end
