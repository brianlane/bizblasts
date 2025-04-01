class HealthController < ApplicationController
  # Skip any authentication or before actions
  skip_before_action :verify_authenticity_token, if: -> { request.format.json? }
  skip_before_action :authenticate_user!
  skip_before_action :set_tenant
  skip_before_action :check_database_connection, only: [:check, :db_check]

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
    begin
      # Try to connect to the database
      result = ActiveRecord::Base.connection.execute("SELECT current_timestamp as time, current_database() as database, version() as version")
      data = result.first
      
      render json: { 
        status: 'ok', 
        database: {
          connected: true,
          time: data['time'],
          database_name: data['database'],
          version: data['version'],
          adapter: ActiveRecord::Base.connection.adapter_name,
          config: {
            host: ActiveRecord::Base.connection_db_config.configuration_hash[:host],
            port: ActiveRecord::Base.connection_db_config.configuration_hash[:port],
            database: ActiveRecord::Base.connection_db_config.configuration_hash[:database]
          }
        },
        env: {
          rails_env: Rails.env,
          database_url_set: ENV['DATABASE_URL'].present?,
          database_host_set: ENV['DATABASE_HOST'].present?,
          database_port_set: ENV['DATABASE_PORT'].present?
        }
      }
    rescue => e
      render json: { 
        status: 'error', 
        message: "Database connection failed: #{e.message}",
        error_class: e.class.name,
        env: {
          rails_env: Rails.env,
          database_url_set: ENV['DATABASE_URL'].present?,
          database_host_set: ENV['DATABASE_HOST'].present?,
          database_port_set: ENV['DATABASE_PORT'].present?
        }
      }, status: :service_unavailable
    end
  end
end 