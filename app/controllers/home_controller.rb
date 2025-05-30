# frozen_string_literal: true

# HomeController handles the main landing page of the application
# It is designed to be resilient to database issues
class HomeController < ApplicationController
  # Skip authentication for index page
  skip_before_action :authenticate_user!, only: [:index]
  # Skip tenant setting for the home page since it's the main domain
  skip_before_action :set_tenant, only: [:index]

  def index
    # Simple landing page without database dependencies
    render :index
  end
end
