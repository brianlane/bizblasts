# frozen_string_literal: true

module Public
  class PaymentsController < ApplicationController
    # Set tenant and require user authentication
    before_action :set_tenant
    before_action :authenticate_user!

    # GET /payments
    def index
      # Placeholder: Fetch payments/history for the current user in this tenant
    end

    # GET /payments/new
    def new
      # Placeholder: Prepare for a new payment (e.g., for an invoice)
      # @invoice = current_tenant.invoices.find_by(id: params[:invoice_id], tenant_customer: current_tenant_customer)
    end

    # POST /payments
    def create
      # Placeholder: Process payment (e.g., via Stripe)
      # This will involve integrating with a payment provider API
      flash[:notice] = "Payment processing coming soon!"
      redirect_to tenant_payments_path # Redirect to index for now
    end

    private

    def current_tenant
      ActsAsTenant.current_tenant
    end

    # Helper to find the TenantCustomer record for the current user in this tenant
    # def current_tenant_customer
    #   @current_tenant_customer ||= current_tenant.tenant_customers.find_by(email: current_user.email) 
    # end
    
    # Re-define set_tenant here IF it's private in ApplicationController
    # def set_tenant
    #   # Copy logic from ApplicationController#set_tenant
    # end
  end
end 