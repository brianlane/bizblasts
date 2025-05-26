# frozen_string_literal: true

module Public
  class PaymentsController < ApplicationController
    # Set tenant and require user authentication
    before_action :set_tenant
    before_action :authenticate_user!, except: [:new, :create]
    before_action :set_tenant_customer, only: [:index, :new, :create]
    before_action :set_invoice, only: [:new, :create]

    # GET /payments
    def index
      @payments = @tenant_customer.payments.successful
    end

    # GET /payments/new?invoice_id=...
    def new
      # Create Stripe Checkout session and redirect to Stripe
      begin
        success_url = tenant_invoice_url(@invoice, payment_success: true, host: request.host_with_port)
        cancel_url = tenant_invoice_url(@invoice, payment_cancelled: true, host: request.host_with_port)
        
        result = StripeService.create_payment_checkout_session(
          invoice: @invoice,
          success_url: success_url,
          cancel_url: cancel_url
        )
        
        redirect_to result[:session].url, allow_other_host: true
      rescue ArgumentError => e
        if e.message.include?("Payment amount must be at least")
          flash[:alert] = "This invoice amount is too small for online payment. Please contact the business directly."
          redirect_to tenant_invoice_path(@invoice)
          return
        else
          raise e
        end
      rescue Stripe::StripeError => e
        flash[:alert] = "Could not connect to Stripe: #{e.message}"
        redirect_to tenant_invoice_path(@invoice)
      end
    end

    # POST /payments - This is now mainly for webhook handling or legacy support
    def create
      # This method can be kept for backward compatibility or webhook processing
      # The main payment flow now goes through Stripe Checkout
      redirect_to tenant_invoice_path(@invoice), notice: 'Please use the payment link to complete your payment.'
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
  end
end 