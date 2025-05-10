module BusinessManager
  class OrdersController < BusinessManager::BaseController
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
      @order = @current_business.orders.includes(
        line_items: { product_variant: :product }, 
        tenant_customer: {}, 
        shipping_method: {}, 
        tax_rate: {}
      ).find(params[:id])
    end
  end
end 