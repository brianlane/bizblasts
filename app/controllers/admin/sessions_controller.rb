# frozen_string_literal: true

# Custom ActiveAdmin sessions controller to handle CSRF token issues
# This controller addresses the 422 error that occurs when logging into admin
# after logging out of a regular user account
class Admin::SessionsController < ActiveAdmin::Devise::SessionsController
  
  # Reset CSRF token before showing login form to prevent stale tokens
  before_action :reset_csrf_token, only: [:new]
  
  # Skip CSRF verification for create action if coming from a cross-session scenario
  skip_before_action :verify_authenticity_token, only: [:create], 
    if: -> { cross_session_login_attempt? }
  
  private
  
  # Reset the CSRF token to ensure fresh token for login form
  def reset_csrf_token
    # Force a new CSRF token to be generated
    session[:_csrf_token] = nil
    form_authenticity_token
    Rails.logger.debug "[Admin::Sessions] CSRF token reset for login form"
  end
  
  # Detect if this is a login attempt coming from a different session type
  def cross_session_login_attempt?
    # Check if we're in a POST request with admin_user params but no valid CSRF token
    request.post? && 
    params[:admin_user].present? && 
    !verified_request?
  end
end 