# frozen_string_literal: true

module Public
  class InvoicesController < ApplicationController
    # Set tenant and allow guest access for invoice viewing
    before_action :set_tenant
    before_action :authenticate_user!, except: [:show]
    before_action :set_tenant_customer, only: [:show]

    # GET /invoices
    def index
      # Placeholder: Fetch invoices for the current user within this tenant
      # @invoices = current_tenant.invoices.where(tenant_customer: current_tenant_customer)
    end

    # GET /invoices/:id?token=...
    def show
      if current_user
        # Authenticated user - verify they own this invoice
        @invoice = current_tenant.invoices.find_by!(id: params[:id])
        @tenant_customer = current_tenant.tenant_customers.find_by!(email: current_user.email)
        unless @invoice.tenant_customer == @tenant_customer
          raise ActiveRecord::RecordNotFound
        end
      else
        # Guest access - require valid token
        if params[:token].present?
          @invoice = current_tenant.invoices.find_by!(id: params[:id], guest_access_token: params[:token])
          @tenant_customer = @invoice.tenant_customer
        else
          # No token provided - redirect to login
          redirect_to new_user_session_path, alert: "Please log in to view this invoice."
          return
        end
      end
    end

    private

    def current_tenant
      ActsAsTenant.current_tenant
    end

    def set_tenant_customer
      if current_user
        @tenant_customer = current_tenant.tenant_customers.find_by!(email: current_user.email)
      else
        # For guest access, tenant_customer will be set in the action method
        @tenant_customer = nil
      end
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