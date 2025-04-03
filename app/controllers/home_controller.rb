# frozen_string_literal: true

# HomeController handles the main landing page of the application
# It is designed to be resilient to database issues
class HomeController < ApplicationController
  # Skip authentication for index page
  skip_before_action :authenticate_user!, only: [:index]
  # For added safety, skip tenant setting for the home page
  skip_before_action :set_tenant, only: [:index]

  def index
    @companies_count = fetch_companies_count
    render :index
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
