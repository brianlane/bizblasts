class InvoicesController < ApplicationController
  before_action :set_tenant, if: -> { before_action_business_domain_check }
  before_action :authenticate_user!
  before_action :set_current_tenant
  before_action :set_tenant_customer

  def index
    if @tenant_customer
      @invoices = @current_tenant.invoices.where(tenant_customer: @tenant_customer)
                                    .includes(booking: [:service, :booking_product_add_ons])
                                    .order(created_at: :desc)
    else
      @invoices = Invoice.none
    end
  end
  
  def show
    if @tenant_customer
      @invoice = @current_tenant.invoices.where(tenant_customer: @tenant_customer)
                                   .includes(booking: [:service, :staff_member, :booking_product_add_ons => {product_variant: :product}], 
                                             line_items: {product_variant: :product},
                                             shipping_method: {}, tax_rate: {})
                                   .find_by(id: params[:id])
      unless @invoice
        flash[:alert] = "Invoice not found or does not belong to you for this business."
        redirect_to invoices_path and return
      end
    else
      flash[:alert] = "Could not identify you as a customer for this business."
      redirect_to root_path and return
    end
  end
  
  def new
    # Placeholder for new invoice form
  end
  
  def create
    # Placeholder for creating an invoice
  end
  
  def edit
    # Placeholder for editing an invoice
  end
  
  def update
    # Placeholder for updating an invoice
  end
  
  def destroy
    # Placeholder for deleting an invoice
  end

  private

  def set_current_tenant
    # Just use what ActsAsTenant already resolved from ApplicationController#set_tenant
    @current_tenant = ActsAsTenant.current_tenant
  end

  def set_tenant_customer
    if @current_tenant && current_user
      @tenant_customer = TenantCustomer.find_by(business_id: @current_tenant.id, email: current_user.email)
    end
  end
end
