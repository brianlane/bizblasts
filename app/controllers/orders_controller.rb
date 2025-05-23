class OrdersController < ApplicationController
  before_action :set_tenant, if: -> { request.subdomain.present? && request.subdomain != 'www' }
  skip_before_action :authenticate_user!
  before_action :authenticate_user!
  before_action :set_current_tenant
  before_action :set_tenant_customer

  def index
    if request.subdomain.present? && request.subdomain != 'www'
      # Tenant-specific case: Show orders only for this business
      if @tenant_customer
        @orders = @tenant_customer.orders.order(created_at: :desc).includes(:line_items, :shipping_method, :tax_rate)
      else
        @orders = Order.none
      end
    else
      # Main domain case: Show all orders for this user across all businesses
      @orders = Order.joins(:tenant_customer)
                     .where(tenant_customers: { email: current_user.email })
                     .order(created_at: :desc)
                     .includes(:line_items, :shipping_method, :tax_rate, :business)
    end
  end

  def show
    if request.subdomain.present? && request.subdomain != 'www'
      # Tenant-specific case
      if @tenant_customer
        @order = @tenant_customer.orders.includes(line_items: { product_variant: :product }).find_by(id: params[:id])
        unless @order
          flash[:alert] = "Order not found or it does not belong to you for this business."
          redirect_to orders_path and return
        end
      else
        flash[:alert] = "Could not identify you as a customer for this business."
        redirect_to root_path and return
      end
    else
      # Main domain case: Show any order that belongs to this user across all businesses
      @order = Order.joins(:tenant_customer)
                   .where(tenant_customers: { email: current_user.email })
                   .includes(line_items: { product_variant: :product })
                   .find_by(id: params[:id])
      
      unless @order
        flash[:alert] = "Order not found or it does not belong to you."
        redirect_to orders_path and return
      end
    end
  end

  def new
    cart = CartManager.new(session).retrieve
    
    unless @tenant_customer
      flash[:alert] = "You must be a registered customer of this business to place an order."
      redirect_to root_path and return
    end
    
    @order = OrderCreator.build_from_cart(cart)
    @order.tenant_customer = @tenant_customer if @tenant_customer
    @order.business = @current_tenant
    
    # Pre-select the default tax rate for this business
    @order.tax_rate = @current_tenant.default_tax_rate
  end

  def create
    unless @tenant_customer
      flash[:alert] = "Action not allowed. Customer profile not found for this business."
      redirect_to root_path and return
    end

    cart = CartManager.new(session).retrieve
    
    # Start with the submitted parameters
    order_creation_params = order_params.merge(
      tenant_customer_id: @tenant_customer.id,
      business_id: @current_tenant.id
    )
    
    # Automatically assign the default tax rate if none provided
    unless order_creation_params[:tax_rate_id].present?
      default_tax_rate = @current_tenant.default_tax_rate
      if default_tax_rate
        order_creation_params[:tax_rate_id] = default_tax_rate.id
      end
    end

    @order = OrderCreator.create_from_cart(cart, order_creation_params)

    if @order.persisted? && @order.errors.empty?
      session[:cart] = {}
      redirect_to order_path(@order), notice: 'Order was successfully created.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def set_current_tenant
    @current_tenant = Business.first
    unless @current_tenant
        Rails.logger.warn "WARN: @current_tenant is not set in OrdersController."
    end
  end

  def set_tenant_customer
    if @current_tenant && current_user
      @tenant_customer = TenantCustomer.find_by(business_id: @current_tenant.id, email: current_user.email)
    end
  end

  def order_params
    params.require(:order).permit(
      :shipping_method_id,
      :tax_rate_id,
      :shipping_address,
      :billing_address,
      :notes,
      line_items_attributes: [:id, :product_variant_id, :quantity, :_destroy]
    )
  end
end 