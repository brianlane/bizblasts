class HomeController < ApplicationController
  # Skip authentication for index page
  skip_before_action :authenticate_user!, only: [:index]
  # For added safety, skip tenant setting for the home page
  skip_before_action :set_tenant, only: [:index]

  def index
    # Safely check if we can connect to the database
    begin
      # Only try to load data if the companies table exists
      if ActiveRecord::Base.connection.table_exists?('companies')
        @companies_count = Company.count
      else
        @companies_count = 0
      end
    rescue => e
      # Log the error but continue with the request
      Rails.logger.error("Error in home controller: #{e.message}")
      @companies_count = 0
    end

    # Render the view
    render :index
  end

  # Action to show which tenant we're currently on
  def debug
    @current_tenant = ActsAsTenant.current_tenant
    @all_tenants = Company.all.pluck(:name, :subdomain)
    @request_subdomain = request.subdomain

    render :debug
  end
end
