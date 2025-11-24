class TransactionsController < ApplicationController
  before_action :set_tenant, if: -> { before_action_business_domain_check }
  before_action :authenticate_user!, except: [:show]
  before_action :set_current_tenant
  before_action :set_tenant_customer

  def index
    @filter = params[:filter] || 'orders' # Default to showing orders
    @transactions = []
    
    if on_business_domain?
      # Tenant-specific case: Show transactions only for this business
      if @tenant_customer
        orders = []
        invoices = []
        
        # Get orders for this business if needed
        if @filter == 'orders' || @filter == 'both'
          orders = @tenant_customer.orders.includes(:line_items, :shipping_method, :tax_rate, :invoice)
        end
        
        # Get invoices for this business if needed
        if @filter == 'invoices' || @filter == 'both'
          invoices = @current_tenant.invoices.where(tenant_customer: @tenant_customer)
                                             .includes(booking: [:service, :booking_product_add_ons])
        end
        
        # Combine and sort by date
        @transactions = (orders.to_a + invoices.to_a).sort_by(&:created_at).reverse
      end
    else
      # Main domain case: Show all transactions for this user across all businesses
      orders = []
      invoices = []
      
      # Use cached tenant customer IDs for better performance
      tenant_customer_ids = current_user.tenant_customer_ids
      
      # Get orders if needed
      if @filter == 'orders' || @filter == 'both'
        orders = Order.joins(:tenant_customer)
                      .where(tenant_customers: { id: tenant_customer_ids })
                      .includes(:line_items, :shipping_method, :tax_rate, :business, :invoice)
      end
      
      # Get invoices if needed
      if @filter == 'invoices' || @filter == 'both'
        invoices = Invoice.joins(:tenant_customer)
                          .where(tenant_customers: { id: tenant_customer_ids })
                          .includes(:business, booking: [:service, :booking_product_add_ons])
      end
      
      # Combine and sort by date
      @transactions = (orders.to_a + invoices.to_a).sort_by(&:created_at).reverse
    end
  end

  def show
    # Check if this is a business manager trying to access an invoice
    if current_user&.has_any_role?(:manager, :staff) && params[:type] == 'invoice' && on_business_domain?
      # Redirect business managers to their invoice management interface
      redirect_to business_manager_invoice_path(params[:id])
      return
    end

    # Find the transaction (either order or invoice)
    if params[:type] == 'invoice'
      @transaction = find_invoice(params[:id])
      @transaction_type = 'invoice'
    else
      @transaction = find_order(params[:id])
      @transaction_type = 'order'
    end

    unless @transaction
      if params[:type] == 'invoice' && !current_user && params[:token].present?
        # Guest user with invalid token - raise 404
        raise ActiveRecord::RecordNotFound
      else
        # Other cases - redirect with flash message
        flash[:alert] = "Transaction not found."
        if on_business_domain?
          redirect_to tenant_transactions_path
        else
          redirect_to transactions_path
        end
      end
    end
  end

  private

  def find_order(id)
    if on_business_domain?
      @tenant_customer&.orders&.includes(
        line_items: { product_variant: :product }, 
        shipping_method: {}, 
        tax_rate: {}, 
        invoice: {}
      )&.find_by(id: id)
    else
      Order.joins(:tenant_customer)
           .where(tenant_customers: { id: current_user.tenant_customer_ids })
           .includes(
             line_items: { product_variant: :product }, 
             shipping_method: {}, 
             tax_rate: {}, 
             business: {}, 
             invoice: {}
           )
           .find_by(id: id)
    end
  end

  def find_invoice(id)
    # FIRST: Handle guest access with token (works on any domain)
    if !current_user && params[:token].present?
      if on_business_domain?
        # Guest access on business domain
        invoice = @current_tenant&.invoices&.includes(booking: [:service, :staff_member, :booking_product_add_ons => {product_variant: :product}],
                                                     line_items: {product_variant: :product},
                                                     shipping_method: {}, tax_rate: {}, order: {})
                                           &.find_by(id: id, guest_access_token: params[:token])
        if invoice
          @tenant_customer = invoice.tenant_customer
          return invoice
        end
      else
        # Guest access on main domain - search across all businesses
        invoice = Invoice.includes(:business, booking: [:service, :staff_member, :booking_product_add_ons => {product_variant: :product}],
                                  line_items: {product_variant: :product},
                                  shipping_method: {}, tax_rate: {}, order: {})
                         .find_by(id: id, guest_access_token: params[:token])
        if invoice
          @tenant_customer = invoice.tenant_customer
          return invoice
        end
      end
      return nil
    end

    # SECOND: Handle authenticated users
    if current_user
      if on_business_domain?
        # Business-specific: Show only this business's invoices
        @current_tenant&.invoices&.where(tenant_customer: @tenant_customer)
                       &.includes(booking: [:service, :staff_member, :booking_product_add_ons => {product_variant: :product}],
                                 line_items: {product_variant: :product},
                                 shipping_method: {}, tax_rate: {}, order: {})
                       &.find_by(id: id)
      else
        # Main domain: Show invoices across all businesses
        Invoice.joins(:tenant_customer)
               .where(tenant_customers: { id: current_user.tenant_customer_ids })
               .includes(:business, booking: [:service, :staff_member, :booking_product_add_ons => {product_variant: :product}],
                         line_items: {product_variant: :product},
                         shipping_method: {}, tax_rate: {}, order: {})
               .find_by(id: id)
      end
    else
      # THIRD: Unauthenticated access without token
      nil
    end
  end

  def set_current_tenant
    # Just use what ActsAsTenant already resolved from ApplicationController#set_tenant
    @current_tenant = ActsAsTenant.current_tenant
  end

  def set_tenant_customer
    if @current_tenant && current_user
      @tenant_customer = TenantCustomer.find_by(business_id: @current_tenant.id, email: current_user.email)
    elsif !current_user && params[:type] == 'invoice' && params[:token].blank?
      # Guest trying to access invoice without token - redirect to login (any domain)
      redirect_to new_user_session_path, alert: "Please log in to view this transaction."
      return false
    end
  end

  def set_tenant
    # Just use what ActsAsTenant already resolved from ApplicationController#set_tenant
    @tenant = ActsAsTenant.current_tenant
  end
end 