# frozen_string_literal: true

# HomeController handles the main landing page of the application
# It is designed to be resilient to database issues
class HomeController < ApplicationController
  # Skip authentication for index page
  skip_before_action :authenticate_user!, only: [:index]
  # For added safety, skip tenant setting for the home page and debug page
  skip_before_action :set_tenant, only: [:index, :debug]

  # Restrict debug action to authenticated admin users
  before_action :authenticate_admin_user!, only: [:debug]
  # Tenant setting is now explicitly skipped above

  def index
    @companies_count = fetch_companies_count
    render :index
  end

  # Action to show which tenant we're currently on
  def debug
    @current_tenant = ActsAsTenant.current_tenant
    @all_tenants = Company.pluck(:name, :subdomain)
    @request_subdomain = request.subdomain

    render :debug
  end

  private

  def fetch_companies_count
    return 0 unless companies_table_exists?
    
    begin
      Company.count
    rescue => e
      Rails.logger.error("Error fetching companies count: #{e.message}")
      0
    end
  end
end
