class Business::OrdersController < Business::BaseController # Assuming you have a BusinessPortal::BaseController for common business-scoped logic
  # before_action :authenticate_business_user! # Or your equivalent for business user authentication
  # The :set_current_business before_action should be in BusinessPortal::BaseController and set @current_business

  def index
    @orders = @current_business.orders.includes(:tenant_customer, :line_items)
    
    # Handle status filter
    if params[:status].present?
      @status_filter = params[:status]
      @orders = @orders.where(status: @status_filter)
    end
    
    # Handle type filter
    if params[:type].present? && Order.order_types.key?(params[:type])
      @type_filter = params[:type]
      @orders = @orders.where(order_type: Order.order_types[@type_filter])
    end
    
    # Sort by most recent
    @orders = @orders.order(created_at: :desc)
  end

  def show
    @order = @current_business.orders.includes(line_items: { product_variant: :product }, tenant_customer: {}, shipping_method: {}, tax_rate: {}).find(params[:id])
    # The .includes is to pre-fetch associated data and avoid N+1 queries in the view.
  end

  # Add other actions like edit, update if business users can modify orders (e.g., update status)
  # For now, just index and show as per the request for "view".

  # Ensure you have a Business::BaseController like this (example):
  # 
  #   class BaseController < ApplicationController
  #     layout 'business' # if you have a specific layout for business section
  #     before_action :authenticate_user! # Or your specific business user authentication
  #     before_action :set_current_business
  #     before_action :authorize_business_access!

  #     private

  #     def set_current_business
  #       # Logic to set @current_business, e.g., from subdomain, user's association, etc.
  #       # This is crucial for all controllers under the BusinessPortal namespace.
  #       # Example: Assuming current_user has a `business` association or similar access control
  #       if current_user.respond_to?(:business) && current_user.business.present?
  #         @current_business = current_user.business
  #         ActsAsTenant.current_tenant = @current_business # If using acts_as_tenant globally
  #       else
  #         # Handle cases where business context cannot be determined or user has no business access
  #         # For example, for a platform admin, you might allow selecting a business.
  #         # For a standard business user, this might be an error or redirect.
  #         # This example assumes a simple direct association for a business user.
  #         @current_business = Business.find_by(subdomain: request.subdomain) if request.subdomain.present?
  #         # Or if user is tied to one business:
  #         # @current_business = current_user.business_managed if current_user.respond_to?(:business_managed)
  #       end

  #       unless @current_business
  #         redirect_to root_path, alert: "Business not found or not accessible."
  #       end
  #     end

  #     def authorize_business_access!
  #       # Verify that the current_user is authorized to manage/view @current_business
  #       # e.g., using Pundit or custom logic
  #       # unless BusinessPolicy.new(current_user, @current_business).access?
  #       #   redirect_to root_path, alert: "You are not authorized to access this business section."
  #       # end
  #       # For simplicity, this is often combined with how @current_business is set.
  #     end
  #   end
  # end
end