class OrdersController < ApplicationController
  def index
    @orders = current_business.orders
  end

  def show
    @order = current_business.orders.find(params[:id])
  end

  def new
    @order = current_business.orders.new
  end

  def create
    @order = current_business.orders.new(order_params)
    
    # Set order type based on line items
    if @order.line_items.all? { |item| item.product? }
      @order.product!
    elsif @order.line_items.all? { |item| item.service? }
      @order.service!  
    else
      @order.mixed!
    end

    if @order.save
      redirect_to @order, notice: 'Order was successfully created.'
    else
      render :new
    end
  end

  private

  def order_params
    params.require(:order).permit(:tenant_customer_id, :shipping_method_id, :tax_rate_id, 
      line_items_attributes: [:id, :lineable_type, :lineable_id, :quantity, :unit_price, :_destroy])
  end
end 