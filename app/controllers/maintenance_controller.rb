# frozen_string_literal: true

# Controller for displaying maintenance pages
# Used during scheduled maintenance and for handling error states
class MaintenanceController < ApplicationController
  # SECURITY: No CSRF skip needed for maintenance/error pages
  # - HTML responses use full CSRF protection
  # - GET-only endpoint that doesn't modify state
  # - Public maintenance/error pages don't require authentication
  # Related: CWE-352 CSRF protection restructuring

  skip_before_action :authenticate_user!  # Public maintenance page
  skip_before_action :check_database_connection  # May be called during DB issues

  # Display maintenance page
  def index
    respond_to do |format|
      format.html { render "errors/maintenance", status: :service_unavailable }
      format.json { render json: { status: 'maintenance', message: 'System is under maintenance' }, status: :service_unavailable }
    end
  end
end
