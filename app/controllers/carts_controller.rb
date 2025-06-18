class CartsController < ApplicationController
  before_action :set_tenant, if: -> { request.subdomain.present? && request.subdomain != 'www' }
  include BusinessAccessProtection
  skip_before_action :authenticate_user!

  def show
    @cart = CartManager.new(session).retrieve
    
    # Show informational message for business users
    if current_user&.staff? || current_user&.manager?
      guard = BusinessAccessGuard.new(current_user, ActsAsTenant.current_tenant, session)
      if guard.should_block_own_business_checkout?
        flash.now[:info] = "As a business user, you'll need to select a customer when you checkout to place this order on their behalf."
      end
    end
  end
end 