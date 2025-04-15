# frozen_string_literal: true

# Controller for displaying maintenance pages
# Used during scheduled maintenance and for handling error states
class MaintenanceController < ApplicationController
  # Skip authentication and database checks
  skip_before_action :verify_authenticity_token, if: -> { request.format.json? }
  skip_before_action :authenticate_user!
  skip_before_action :check_database_connection

  # Display maintenance page
  def index
    render "errors/maintenance", status: :service_unavailable
  end
end
