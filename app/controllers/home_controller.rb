# frozen_string_literal: true

# HomeController handles the main landing page of the application
# It is designed to be resilient to database issues
class HomeController < ApplicationController
  # Skip authentication for index page, marketing pages, and platform legal pages.
  # Legal pages must work for signed-out visitors on the main domain, on tenant
  # subdomains, and on tenant custom domains (e.g. https://www.losnemassageaz.com/terms).
  skip_before_action :authenticate_user!, only: [:index, :about, :contact, :cookies, :privacy, :terms, :disclaimer, :shippingpolicy, :returnpolicy, :acceptableusepolicy, :pricing, :check_business_industry]

  # Skip tenant setting only for the marketing-only pages (index/about/contact/pricing).
  # The legal pages (cookies/privacy/terms/disclaimer/shippingpolicy/returnpolicy/
  # acceptableusepolicy) intentionally run set_tenant so that when they are served
  # from a tenant subdomain or custom domain, the layout can render the tenant's
  # footer/branding and preserve cross-domain auth context. set_tenant is a no-op
  # on the main domain, so this is also safe there.
  skip_before_action :set_tenant, only: [:index, :about, :contact, :pricing, :check_business_industry]

  def index
    # Simple landing page without database dependencies
    # Load categorized business examples from the Business model
    @showcase_categories = Business.showcase_categories

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
