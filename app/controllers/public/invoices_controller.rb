# frozen_string_literal: true

module Public
  class InvoicesController < ApplicationController
    # Set tenant and require user authentication
    before_action :set_tenant
    before_action :authenticate_user!
    before_action :set_tenant_customer, only: [:show]

    # GET /invoices
    def index
      # Placeholder: Fetch invoices for the current user within this tenant
      # @invoices = current_tenant.invoices.where(tenant_customer: current_tenant_customer)
    end

    # GET /invoices/:id
    def show
      # Fetch specific invoice for this user
      @tenant_customer = current_tenant.tenant_customers.find_by!(email: current_user.email)
      @invoice = current_tenant.invoices.find_by!(id: params[:id], tenant_customer: @tenant_customer)
    end

    private

    def current_tenant
      ActsAsTenant.current_tenant
    end

    def set_tenant_customer
      @tenant_customer = current_tenant.tenant_customers.find_by!(email: current_user.email)
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