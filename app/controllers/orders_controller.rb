class OrdersController < ApplicationController
  before_action :set_tenant, if: -> { request.subdomain.present? && request.subdomain != 'www' }
  skip_before_action :authenticate_user!

  def index
    @orders = current_tenant.orders
  end

  def show
    @order = current_tenant.orders.find(params[:id])
  end

  def new
    cart = CartManager.new(session).retrieve
    @order = OrderCreator.build_from_cart(cart)
  end

  def create
    cart = CartManager.new(session).retrieve
    @order = OrderCreator.create_from_cart(cart, order_params)
    if @order.persisted? && @order.errors.empty?
      session[:cart] = {} # Clear cart
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