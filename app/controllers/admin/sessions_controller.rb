# frozen_string_literal: true

# Custom ActiveAdmin sessions controller to handle CSRF token issues
# This controller addresses the 422 error that occurs when logging into admin
# after logging out of a regular user account
class Admin::SessionsController < ActiveAdmin::Devise::SessionsController

  # Reset CSRF token before showing login form to prevent stale tokens
  before_action :reset_csrf_token, only: [:new]

  # Handle CSRF verification failures gracefully by regenerating token and re-rendering form
  rescue_from ActionController::InvalidAuthenticityToken, with: :handle_invalid_token

  private

  # Reset the CSRF token to ensure fresh token for login form
  def reset_csrf_token
    # Force a new CSRF token to be generated
    session[:_csrf_token] = nil
    form_authenticity_token
    Rails.logger.debug "[Admin::Sessions] CSRF token reset for login form"
  end

  # Handle invalid CSRF tokens by regenerating and showing error
  def handle_invalid_token
    # Only handle this for login attempts, not for other potential actions
    if request.post? && action_name == 'create'
      Rails.logger.warn "[Admin::Sessions] Invalid CSRF token detected for login attempt from IP: #{request.remote_ip}"

      # Regenerate the CSRF token for a fresh attempt
      reset_csrf_token

      # Rebuild the resource so the login form has a model instance
      build_resource({})

      # Set an error message
      flash.now[:error] = "Your session has expired. Please try logging in again."

      # Re-render the login form with the fresh token
      render :new, status: :unprocessable_content
    else
      # For other actions, use default Rails behavior
      raise ActionController::InvalidAuthenticityToken
    end
  end
end 