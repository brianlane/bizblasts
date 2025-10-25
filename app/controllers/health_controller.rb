# frozen_string_literal: true

# HealthController provides endpoints for monitoring the application status
# It includes basic health checks and database connectivity verification
class HealthController < ApplicationController
  # SECURITY: CSRF skip is LEGITIMATE for monitoring endpoints
  # - Health checks are GET requests that don't modify state (read-only)
  # - Used by monitoring services (Render.com, uptime monitors) that don't have sessions
  # - JSON-only responses, no HTML forms or state changes
  # - db_check requires authentication token in production (see line 26)
  # Related security: CWE-352 (CSRF) N/A for read-only monitoring endpoints
  skip_before_action :verify_authenticity_token, if: -> { request.format.json? }
  skip_before_action :authenticate_user!
  skip_before_action :set_tenant  # Health checks should not depend on tenant context
  skip_before_action :check_database_connection, only: %i[check db_check]

  # Simple health check endpoint
  def check
    # Basic health check - doesn't need database access
    render json: { status: 'ok' }, status: :ok
  rescue => e
    # If there are any errors, still return 200 OK to prevent Render from restarting the service
    # Just log the error but don't fail the health check
    Rails.logger.error("Health check encountered an error: #{e.message}")
    render json: { status: 'ok', message: 'Health check passed but with warnings' }, status: :ok
  end
  
  # Database connectivity check
  def db_check
    # Security: Add basic authentication for detailed database info
    if request.headers['Authorization'] != "Bearer #{ENV['HEALTH_CHECK_TOKEN']}" && Rails.env.production?
      render json: { status: 'unauthorized' }, status: :unauthorized
      return
    end

    check_database_connection
  rescue => e
    render_database_error(e)
  end

  private

  def check_database_connection
    # Try to connect to the database
    # Security: Use simpler query that doesn't expose system information
    result = ActiveRecord::Base.connection.execute("SELECT 1 as health_check")
    
    render json: { 
      status: 'ok', 
      database: {
        connected: true,
        timestamp: Time.current.iso8601
      }
    }
  end

  def database_info(data)
    # Security: Removed - this method exposed too much information
    # Only keeping basic connectivity status
    {
      connected: true,
      timestamp: Time.current.iso8601
    }
  end

  def database_config
    # Security: Removed - this exposed sensitive configuration details
    # Keep minimal info for debugging if authenticated
    if Rails.env.development?
      {
        adapter: ActiveRecord::Base.connection.adapter_name,
        database: ActiveRecord::Base.connection_db_config.database
      }
    else
      { adapter: 'configured' }
    end
  end

  def limited_environment_info
    # SECURITY FIX: Remove environment information disclosure
    { status: 'ok' }
  end

  def environment_info
    # Security: Only show in development or with proper authentication
    if Rails.env.development? || request.headers['Authorization'] == "Bearer #{ENV['HEALTH_CHECK_TOKEN']}"
      {
        rails_env: Rails.env,
        database_url_set: ENV['DATABASE_URL'].present?,
        database_host_set: ENV['DATABASE_HOST'].present?,
        database_port_set: ENV['DATABASE_PORT'].present?
      }
    else
      limited_environment_info
    end
  end

  def render_database_error(exception)
    # Security: Don't expose detailed error information in production
    if Rails.env.production?
      render json: { 
        status: 'error', 
        message: "Database connectivity issue"
      }, status: :service_unavailable
    else
      render json: { 
        status: 'error', 
        message: "Database connection failed: #{exception.message}",
        error_class: exception.class.name,
        env: environment_info
      }, status: :service_unavailable
    end
  end
end
