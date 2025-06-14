# frozen_string_literal: true

# Concern to protect against business users accessing other businesses' booking/cart functionality
module BusinessAccessProtection
  extend ActiveSupport::Concern

  included do
    before_action :prevent_cross_business_access, if: :should_check_business_access?
  end

  private

  # Check if we should enforce business access protection
  def should_check_business_access?
    # Only check on tenant subdomains/domains, not main site
    current_tenant.present? && current_user.present?
  end

  # Prevent business users from accessing other businesses
  def prevent_cross_business_access
    guard = BusinessAccessGuard.new(current_user, current_tenant, session)
    
    if guard.should_block_access?
      # Log the security event
      guard.log_blocked_access
      
      # Clear any cart items from the other business
      guard.clear_cross_business_cart_items!
      
      # Set flash message and redirect
      flash[:alert] = guard.flash_message
      redirect_to guard.redirect_path and return
    end
  end

  # Helper method to get current tenant (compatible with existing code)
  def current_tenant
    ActsAsTenant.current_tenant
  end
end 