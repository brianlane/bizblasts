# frozen_string_literal: true

# HomeController handles the main landing page of the application
# It is designed to be resilient to database issues
class HomeController < ApplicationController
  # Skip authentication for index page and new static pages
  skip_before_action :authenticate_user!, only: [:index, :about, :contact, :cookies, :privacy, :terms]
  # Skip tenant setting for the home page since it's the main domain
  skip_before_action :set_tenant, only: [:index, :about, :contact, :cookies, :privacy, :terms]

  def index
    # Simple landing page without database dependencies
    render :index
  end

  def about
    render :about
  end

  def contact
    render :contact
  end

  def cookies
    render :cookies
  end

  def privacy
    render :privacy
  end

  def terms
    render :terms
  end
end
