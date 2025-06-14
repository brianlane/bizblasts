# frozen_string_literal: true

# Service to prevent business users from accessing booking/cart functionality on other businesses
class BusinessAccessGuard
  attr_reader :current_user, :current_business, :session

  def initialize(current_user, current_business, session = nil)
    @current_user = current_user
    @current_business = current_business
    @session = session
  end

  # Check if current user should be blocked from accessing booking/cart functionality
  def should_block_access?
    return false unless current_user.present?
    return false if current_user.client? # Clients can access any business

    # Block business users (manager/staff) from accessing other businesses
    business_user_accessing_different_business?
  end

  # Get appropriate flash message for blocked access
  def flash_message
    return nil unless should_block_access?
    "You must sign out and proceed as a guest to access this business. Business users can only access their own business's booking and shopping features."
  end

  # Get redirect path for blocked users (simple version)
  def redirect_path
    '/'
  end

  # Clear cart if business user is accessing different business
  def clear_cross_business_cart_items!
    return unless session.present?

    if session[:cart].present?
      Rails.logger.warn "[BusinessAccessGuard] Clearing cart for business user #{current_user.id} accessing different business #{current_business&.id}"
      session[:cart] = nil
    end
  end

  # Log access attempt for security monitoring
  def log_blocked_access
    business_id = current_business&.id || 'nil'
    Rails.logger.warn "[SECURITY] Business user #{current_user.id} (#{current_user.role}) from business #{current_user.business_id} attempted to access business #{business_id}. Access blocked."
  end

  private

  # Check if user is business staff/manager trying to access different business
  def business_user_accessing_different_business?
    return false unless current_user.present?
    return false unless current_user.manager? || current_user.staff?
    return false unless current_business.present?
    return false unless current_user.business_id.present?

    current_user.business_id != current_business.id
  end
end 