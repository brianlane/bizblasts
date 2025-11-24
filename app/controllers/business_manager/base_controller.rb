# frozen_string_literal: true

# Base controller for the Business Manager section.
# Handles authentication and authorization for business users (managers and staff).
class BusinessManager::BaseController < ApplicationController
  layout 'business_manager'

  # Ensure user is signed in before any action in this namespace
  before_action :authenticate_user!
  
  # Set the tenant *after* user is authenticated
  before_action :set_tenant_for_business_manager, unless: -> { maintenance_mode? }

  # Authorize access using Pundit after tenant and user are set.
  # Note: @current_business is set by set_tenant_for_business_manager
  before_action :authorize_access_to_business_manager

  # Check business setup and set flash for managers (not staff)
  before_action :check_business_setup, if: -> { current_user&.manager? }
  
  # Handle routing errors gracefully
  rescue_from ActionController::RoutingError, with: :handle_routing_error

  # Endpoint to record dismissal of a specific business setup reminder task for the current user
  def dismiss_setup_reminder
    key = params[:key]
    # Record the dismissal time, avoid duplicates
    current_user.setup_reminder_dismissals.find_or_create_by!(task_key: key) do |dismissal|
      dismissal.dismissed_at = Time.current
    end
    head :no_content
  end

  protected

  # Check business setup completion and set todo flash for managers
  def check_business_setup
    return unless current_business

    @business_setup_service = BusinessSetupService.new(current_business, current_user)
    
    # Only show setup todos if there are incomplete items AND visible todo items remaining
    unless @business_setup_service.setup_complete? || @business_setup_service.todo_items.empty?
      setup_flash_content = render_to_string(
        partial: 'shared/business_setup_todos',
        locals: { setup_service: @business_setup_service }
      )
      flash.now[:business_setup] = setup_flash_content.html_safe
    end
  end

  private

  def authorize_access_to_business_manager
    # Redirect to login if no user is signed in
    unless current_user
      redirect_to new_user_session_path and return
    end
    # Ensure we actually have a business context before authorizing
    unless current_business
      Rails.logger.warn "[BusinessManager Auth] No current_business found. Redirecting to root."
      flash[:alert] = "Could not identify the business context."
      redirect_to root_path and return
    end
    
    # Check if user is a client or doesn't belong to this business
    if current_user.client?
      Rails.logger.warn "[BusinessManager Auth] Client user #{current_user.id} attempted to access Business Manager for business #{current_business.id}"
      flash[:alert] = "You are not authorized to access this area."
      redirect_to dashboard_path and return
    elsif current_user.business_id != current_business.id
      Rails.logger.warn "[BusinessManager Auth] User #{current_user.id} (#{current_user.role}) attempted to access Business Manager for business #{current_business.id}"
      flash[:alert] = "You are not authorized to access this area."
      redirect_to root_path and return
    end
    
    # Authorize using Pundit. Assumes BusinessPolicy has access_business_manager?
    authorize current_business, :access_business_manager?
  end

  # Helper method to access the current business tenant within this namespace
  def current_business
    # Use the tenant set by ApplicationController
    @current_business ||= ActsAsTenant.current_tenant
  end

  # Define the tenant setting method specifically for this controller
  # This method now works with both subdomains and custom domains
  def set_tenant_for_business_manager
    # The ApplicationController has already set the tenant via set_tenant method
    # which handles both custom domains and subdomains
    if ActsAsTenant.current_tenant.present?
      Rails.logger.debug "[BusinessManager] Using tenant set by ApplicationController: #{ActsAsTenant.current_tenant.hostname}"
      return
    end

    # If no tenant was set by ApplicationController, this is an error condition
    Rails.logger.error "[BusinessManager] No tenant found - neither subdomain nor custom domain matched"
    flash[:alert] = "Business not found."
    redirect_to root_path
  end
  
  private
  
  def handle_routing_error
    Rails.logger.warn "BusinessManager: Routing error for path: #{request.path}"
    flash[:alert] = "The page you're looking for doesn't exist."
    redirect_to business_manager_root_path
  end
end 