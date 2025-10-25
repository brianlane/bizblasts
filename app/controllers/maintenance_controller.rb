# frozen_string_literal: true

# Controller for displaying maintenance pages
# Used during scheduled maintenance and for handling error states
class MaintenanceController < ApplicationController
  # SECURITY: CSRF skip is LEGITIMATE for maintenance/error pages
  # - Maintenance page is informational only, doesn't modify state
  # - Displayed when system is unavailable or in maintenance mode
  # - No user interactions or state changes possible
  # - JSON format is for monitoring systems to check maintenance status
  # Related security: CWE-352 (CSRF) N/A for static error pages
  skip_before_action :verify_authenticity_token, if: -> { request.format.json? }
  skip_before_action :authenticate_user!
  skip_before_action :check_database_connection

  # Display maintenance page
  def index
    render "errors/maintenance", status: :service_unavailable
  end
end
