# frozen_string_literal: true

module Public
  class InvoicesController < ApplicationController
    # Set tenant and allow guest access for invoice viewing
    before_action :set_tenant
    before_action :authenticate_user!, except: [:show, :pay]
    before_action :set_invoice_and_access_token, only: [:show, :pay]

    # GET /invoices
    def index
      # Placeholder: Fetch invoices for the current user within this tenant
      # @invoices = current_tenant.invoices.where(tenant_customer: current_tenant_customer)
    end

    # GET /invoices/:id?token=...
    def show
      # Invoice and access token are already set by before_action
    end

    def pay
      # Extract tip amount if provided
      tip_amount = params[:tip_amount].to_f if params[:tip_amount].present?
      
      # Check if tips are enabled and validate tip amount
      if tip_amount.present? && tip_amount > 0
        unless current_tenant.tips_enabled?
          flash[:alert] = "Tips are not enabled for this business."
          redirect_to tenant_invoice_path(@invoice, access_token: @access_token) and return
        end
        
        if tip_amount < 0.50
          flash[:alert] = "Minimum tip amount is $0.50."
          redirect_to tenant_invoice_path(@invoice, access_token: @access_token) and return
        end
        
        # Update invoice with tip amount
        @invoice.update!(tip_amount: tip_amount)
      end

      # Ensure payment isn't already completed
      if @invoice.status == 'paid'
        flash[:notice] = 'This invoice has already been paid.'
        redirect_to tenant_invoice_path(@invoice, access_token: @access_token) and return
      end

      begin
        # Create Stripe checkout session with tip included
        success_url = if tip_amount.present? && tip_amount > 0
                        tenant_invoice_url(@invoice, payment_success: true, tip_included: true, access_token: @access_token, host: request.host_with_port)
                      else
                        tenant_invoice_url(@invoice, payment_success: true, access_token: @access_token, host: request.host_with_port)
                      end
        cancel_url = tenant_invoice_url(@invoice, payment_cancelled: true, access_token: @access_token, host: request.host_with_port)
        
        result = StripeService.create_payment_checkout_session(
          invoice: @invoice,
          success_url: success_url,
          cancel_url: cancel_url
        )
        
        redirect_to result[:session].url, allow_other_host: true
      rescue ArgumentError => e
        if e.message.include?("Payment amount must be at least")
          flash[:alert] = "This invoice amount is too small for online payment. Please contact the business directly."
          redirect_to tenant_invoice_path(@invoice, access_token: @access_token)
        else
          raise e
        end
      rescue Stripe::StripeError => e
        flash[:alert] = "Could not connect to Stripe: #{e.message}"
        redirect_to tenant_invoice_path(@invoice, access_token: @access_token)
      end
    end

    private

    def set_invoice_and_access_token
      @access_token = params[:access_token] || params[:token]
      
      if @access_token.present?
        # Guest access via token
        @invoice = current_tenant.invoices.find_by!(id: params[:id], guest_access_token: @access_token)
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