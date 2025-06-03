# frozen_string_literal: true

module Public
  class InvoicesController < ApplicationController
    # Set tenant and allow guest access for invoice viewing
    before_action :set_tenant
    before_action :authenticate_user!, except: [:show]

    # GET /invoices
    def index
      # Placeholder: Fetch invoices for the current user within this tenant
      # @invoices = current_tenant.invoices.where(tenant_customer: current_tenant_customer)
    end

    # GET /invoices/:id?token=...
    def show
      if params[:token].present?
        # Guest access via token
        @invoice = current_tenant.invoices.find_by!(id: params[:id], guest_access_token: params[:token])
        @tenant_customer = @invoice.tenant_customer
      elsif current_user && (customer = current_tenant.tenant_customers.find_by(email: current_user.email))
        # Authenticated tenant customer access
        @tenant_customer = customer
        @invoice = current_tenant.invoices.find_by!(id: params[:id], tenant_customer: @tenant_customer)
      else
        # No valid access - require token or login
        redirect_to new_user_session_path, alert: "Please log in to view this invoice."
        return
      end
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