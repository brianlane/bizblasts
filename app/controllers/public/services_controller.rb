class Public::ServicesController < ApplicationController
  # Public pages should not require authentication
  skip_before_action :authenticate_user!
  before_action :set_tenant
  # Make sure to inherit from Public::BaseController or similar to handle tenant scoping
  
  def show
    # Find the service by ID, ensuring it belongs to the current tenant
    @service = current_tenant.services.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    # Handle case where service is not found or doesn't belong to the tenant
    redirect_to tenant_services_page_path, alert: "Service not found."
  end
  
  # Other actions (like index) could be added here later if needed
end 