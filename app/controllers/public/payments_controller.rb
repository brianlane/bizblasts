# frozen_string_literal: true

module Public
  class PaymentsController < Public::BaseController
    skip_before_action :authenticate_user!, only: %i[new create]
    # Set tenant and require user authentication
    before_action :set_tenant
    before_action :authenticate_user!, except: %i[new create]
    before_action :set_tenant_customer, only: %i[index new create]
    before_action :set_invoice, only: %i[new create]

    after_action :no_store!, only: %i[new create]

    # GET /payments
    def index
      @payments = @tenant_customer.payments.successful
    end

    # GET /payments/new?invoice_id=...
    def new
      # Create Stripe Checkout session and redirect to Stripe
      begin
        # For guest users, include the token in the success/cancel URLs
        url_params = { type: 'invoice', payment_success: true, host: request.host_with_port }
        cancel_params = { type: 'invoice', payment_cancelled: true, host: request.host_with_port }
        
        unless current_user
          # For guest users, still redirect to invoice view with token since they can't access transactions
          url_params = { payment_success: true, host: request.host_with_port, token: @invoice.guest_access_token }
          cancel_params = { payment_cancelled: true, host: request.host_with_port, token: @invoice.guest_access_token }
          success_url = tenant_invoice_url(@invoice, url_params)
          cancel_url = tenant_invoice_url(@invoice, cancel_params)
        else
          # For authenticated users, redirect to transactions view
          success_url = tenant_transaction_url(@invoice, url_params)
          cancel_url = tenant_transaction_url(@invoice, cancel_params)
        end
        
        result = StripeService.create_payment_checkout_session(
          invoice: @invoice,
          success_url: success_url,
          cancel_url: cancel_url
        )
        
        redirect_to result[:session].url, allow_other_host: true
      rescue ArgumentError => e
        if e.message.include?("Payment amount must be at least")
          flash[:alert] = "This invoice amount is too small for online payment. Please contact the business directly."
          redirect_to_invoice_with_token
          return
        else
          raise e
        end
      rescue Stripe::StripeError => e
        flash[:alert] = "Could not connect to Stripe: #{e.message}"
        redirect_to_invoice_with_token
      end
    end

    # POST /payments - This is now mainly for webhook handling or legacy support
    def create
      # This method can be kept for backward compatibility or webhook processing
      # The main payment flow now goes through Stripe Checkout
      redirect_to_invoice_with_token(notice: 'Please use the payment link to complete your payment.')
    end

    private

    def current_tenant
      ActsAsTenant.current_tenant
    end

    def set_tenant_customer
      if current_user
        @tenant_customer = current_tenant.tenant_customers.find_by(email: current_user.email)
        raise ActiveRecord::RecordNotFound unless @tenant_customer
      else
        # For guest checkout, find tenant customer from invoice
        invoice = current_tenant.invoices.find_by(id: params[:invoice_id])
        @tenant_customer = invoice&.tenant_customer
        raise ActiveRecord::RecordNotFound unless @tenant_customer
      end
    end

    def set_invoice
      @invoice = current_tenant.invoices.find_by(id: params[:invoice_id])
      # Verify the invoice belongs to the tenant customer
      if @tenant_customer && @invoice&.tenant_customer != @tenant_customer
        raise ActiveRecord::RecordNotFound
      end
      raise ActiveRecord::RecordNotFound unless @invoice
    end

    def redirect_to_invoice_with_token(flash_options = {})
      if current_user
        redirect_to tenant_transaction_path(@invoice, type: 'invoice'), flash_options
      else
        redirect_to tenant_invoice_path(@invoice, token: @invoice.guest_access_token), flash_options
      end
    end
  end
end 