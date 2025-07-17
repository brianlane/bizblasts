class Public::ServicesController < ApplicationController
  # Public pages should not require authentication
  skip_before_action :authenticate_user!
  before_action :set_tenant
  # Make sure to inherit from Public::BaseController or similar to handle tenant scoping
  
  def show
    # Find the service by ID, ensuring it belongs to the current tenant
    @service = current_tenant.services.find(params[:id])

    # Handle service variant selection with proper fallback logic
    if params[:service_variant_id].present?
      @service_variant = @service.service_variants.find_by(id: params[:service_variant_id])
    end
    
    # Auto-select default variant if no variant specified or invalid variant provided
    if @service_variant.nil? && @service.service_variants.active.any?
      @service_variant = @service.service_variants.active.by_position.first
    end
  rescue ActiveRecord::RecordNotFound
    # Handle case where service is not found or doesn't belong to the tenant
    redirect_to tenant_services_page_path, alert: "Service not found."
  end
  
  # Other actions (like index) could be added here later if needed
end 