# frozen_string_literal: true

# HealthController provides endpoints for monitoring the application status
# It includes basic health checks and database connectivity verification
class HealthController < ApplicationController
  # Skip any authentication or before actions
  skip_before_action :verify_authenticity_token, if: -> { request.format.json? }
  skip_before_action :authenticate_user!
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
    check_database_connection
  rescue => e
    render_database_error(e)
  end

  private

  def check_database_connection
    # Try to connect to the database
    result = ActiveRecord::Base.connection.execute(
      "SELECT current_timestamp as time, current_database() as database, version() as version"
    )
    data = result.first
    
    render json: { 
      status: 'ok', 
      database: database_info(data),
      env: environment_info
    }
  end

  def database_info(data)
    {
      connected: true,
      time: data['time'],
      database_name: data['database'],
      version: data['version'],
      adapter: ActiveRecord::Base.connection.adapter_name,
      config: database_config
    }
  end

  def database_config
    {
      host: ActiveRecord::Base.connection_db_config.configuration_hash[:host],
      port: ActiveRecord::Base.connection_db_config.configuration_hash[:port],
      database: ActiveRecord::Base.connection_db_config.configuration_hash[:database]
    }
  end

  def environment_info
    {
      rails_env: Rails.env,
      database_url_set: ENV['DATABASE_URL'].present?,
      database_host_set: ENV['DATABASE_HOST'].present?,
      database_port_set: ENV['DATABASE_PORT'].present?
    }
  end

  def render_database_error(exception)
    render json: { 
      status: 'error', 
      message: "Database connection failed: #{exception.message}",
      error_class: exception.class.name,
      env: environment_info
    }, status: :service_unavailable
  end
end
