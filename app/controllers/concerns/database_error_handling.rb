# frozen_string_literal: true

# Concern for handling database-related errors
# Provides methods for gracefully handling various database issues
module DatabaseErrorHandling
  extend ActiveSupport::Concern

  included do
    rescue_from ActiveRecord::ConnectionNotEstablished, with: :database_connection_error
    rescue_from PG::UndefinedTable, with: :handle_undefined_table
    rescue_from ActiveRecord::StatementInvalid, with: :handle_statement_invalid
  end

  protected

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
      format.json do
        render json: { error: 'Database table error', details: exception.message }, status: :service_unavailable
      end
    end
  end

  def handle_statement_invalid(exception)
    Rails.logger.error("SQL Statement error: #{exception.message}")

    # Fallback to maintenance mode
    render_statement_invalid_response(exception)
  end

  def render_statement_invalid_response(exception)
    respond_to do |format|
      format.html { render template: "errors/maintenance", status: :service_unavailable }
      format.json { render json: { error: 'Database error', details: exception.message }, status: :service_unavailable }
    end
  end
end
