# frozen_string_literal: true

# HomeController handles the main landing page of the application
# It is designed to be resilient to database issues
class HomeController < ApplicationController
  # Skip authentication for index page
  skip_before_action :authenticate_user!, only: [:index]
  # For added safety, skip tenant setting for the home page
  # skip_before_action :set_tenant, only: [:index] # REMOVED: Global filter was removed

  def index
    @companies_count = fetch_companies_count
    render :index
  end

  private

  def fetch_companies_count
    # Check specifically for businesses table now
    return 0 unless ActiveRecord::Base.connection.table_exists?('businesses')
    
    begin
      # Count businesses instead of companies
      Business.count 
    rescue => e
      Rails.logger.error("Error fetching businesses count: #{e.message}")
      0
    end
  end
end
