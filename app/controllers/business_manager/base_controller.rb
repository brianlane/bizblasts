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

  protected

  # Check business setup completion and set todo flash for managers
  def check_business_setup
    return unless current_business

    @business_setup_service = BusinessSetupService.new(current_business)
    
    # Only show setup todos if there are incomplete items
    unless @business_setup_service.setup_complete?
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
  def set_tenant_for_business_manager
    hostname = request.subdomain.presence
    if hostname.present? && hostname != "www"
      unless businesses_table_exists?
        Rails.logger.error("Businesses table missing, cannot set tenant for BusinessManager")
        flash[:alert] = "Application error: Business context unavailable."
        redirect_to root_path and return # Or handle appropriately
      end

      unless find_and_set_business_tenant(hostname)
        Rails.logger.warn "BusinessManager: Tenant not found for hostname: #{hostname}"
        tenant_not_found # Reuse existing handler
      end
    else
      # Should not happen if accessed via subdomain route constraint, but handle defensively
      Rails.logger.error "BusinessManager accessed without a valid subdomain."
      flash[:alert] = "Invalid access method."
      redirect_to root_path
    end
  end
end 