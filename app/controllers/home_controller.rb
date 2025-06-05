# frozen_string_literal: true

# HomeController handles the main landing page of the application
# It is designed to be resilient to database issues
class HomeController < ApplicationController
  # Skip authentication for index page and new static pages
  skip_before_action :authenticate_user!, only: [:index, :about, :contact, :cookies, :privacy, :terms, :disclaimer, :shippingpolicy, :returnpolicy, :acceptableusepolicy, :pricing, :check_business_industry]
  # Skip tenant setting for the home page since it's the main domain
  skip_before_action :set_tenant, only: [:index, :about, :contact, :cookies, :privacy, :terms, :disclaimer, :shippingpolicy, :returnpolicy, :acceptableusepolicy, :pricing, :check_business_industry]

  def index
    # Simple landing page without database dependencies
    # Load and categorize business examples for the showcase
    all_industries = Business::SHOWCASE_INDUSTRY_MAPPINGS.values
    
    # Define approximate splits for categories. Adjust as needed.
    # These are just example counts; the actual number of examples for each
    # category will depend on the SHOWCASE_INDUSTRY_MAPPINGS content.
    # The goal is to get roughly 30 examples per category as per original JS.
    # We'll take the first 30 for services, next 30 for experiences, and the rest for products.
    # Note: This assumes SHOWCASE_INDUSTRY_MAPPINGS is ordered implicitly or explicitly
    # in a way that the first ~30 are services, next ~30 are experiences, etc.
    # If the order in SHOWCASE_INDUSTRY_MAPPINGS changes, this logic might need adjustment
    # or a more robust categorization method (e.g., adding a category key to the mapping).
    
    # For simplicity, we'll hardcode the expected number of items per category from the original JS.
    # It's better to have a more robust way to categorize if the source data isn't strictly ordered.
    # However, given the current structure of SHOWCASE_INDUSTRY_MAPPINGS, we'll take slices.
    
    # Let's try to maintain the original 30 examples for each category for now,
    # assuming the mapping has enough entries and is somewhat ordered.
    # The original JS had 30 for Services, 30 for Experiences, and 30 for Products.

    # Replicating the categories and roughly the number of examples from original JS
    # This is a simplified approach. For more dynamic categorization,
    # SHOWCASE_INDUSTRY_MAPPINGS would need to include category information.
    
    # Based on the SHOWCASE_INDUSTRY_MAPPINGS in business.rb:
    # Services: first 30 (hair_salons to it_support)
    # Experiences: next 30 (yoga_classes to spa_days)
    # Products: next 30 (boutiques to farmers_markets) - or fewer if total is less
    
    services_count = 30
    experiences_count = 30
    # Products count will be the remainder or 30, whichever is smaller.

    # Get all unique industry values from the mapping
    unique_industries = Business.industries.values.uniq - ["Other"] # Exclude "Other"

    # Assign examples based on the order in SHOWCASE_INDUSTRY_MAPPINGS
    # We'll take the first 30 for services, next 30 for experiences, and the following for products.
    # This implicitly relies on the order in SHOWCASE_INDUSTRY_MAPPINGS.
    
    # Extracting values from the SHOWCASE_INDUSTRY_MAPPINGS directly
    # to preserve the intended order and content.
    mapped_values = Business::SHOWCASE_INDUSTRY_MAPPINGS.values.reject { |v| v == "Other" }

    @showcase_categories = {
      "Services" => mapped_values.slice(0, services_count) || [],
      "Experiences" => mapped_values.slice(services_count, experiences_count) || [],
      "Products" => mapped_values.slice(services_count + experiences_count, 30) || [] # Max 30 for products as well
    }
    
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

  def disclaimer
    render :disclaimer
  end

  def shippingpolicy
    render :shippingpolicy
  end

  def returnpolicy
    render :returnpolicy
  end

  def acceptableusepolicy
    render :acceptableusepolicy
  end

  def pricing
    render :pricing
  end

  def check_business_industry
    industry_name = params[:industry]
    exists = Business.where("LOWER(industry) = LOWER(?)", industry_name).exists?
    render json: { exists: exists }
  end
end
