class StripeAppTestController < ApplicationController
  # Skip authentication and tenant scoping for this test endpoint
  skip_before_action :authenticate_user!
  skip_before_action :set_tenant
  
  def show
    # This renders the test page for deep link validation
    render 'stripe_app_test', layout: false
  end
end