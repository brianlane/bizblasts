# frozen_string_literal: true

module Public
  class PaymentsController < ApplicationController
    # Set tenant and require user authentication
    before_action :set_tenant
    before_action :authenticate_user!, except: [:new, :create]
    before_action :set_tenant_customer, only: [:index, :new, :create]
    before_action :set_invoice, only: [:new, :create]
    before_action :set_stripe_publishable_key, only: [:new, :create]

    # GET /payments
    def index
      @payments = @tenant_customer.payments.successful
    end

    # GET /payments/new?invoice_id=...
    def new
      # invoice loaded by before_action
      # new view will mount Stripe Elements with @stripe_publishable_key and @client_secret
      begin
        result = StripeService.create_payment_intent(invoice: @invoice)
        @client_secret = result[:client_secret]
      rescue ArgumentError => e
        if e.message.include?("Payment amount must be at least")
          flash[:alert] = "This invoice amount is too small for online payment. Please contact the business directly."
          redirect_to tenant_invoice_path(@invoice)
          return
        else
          raise e
        end
      end
    end

    # POST /payments
    def create
      # Process payment: confirm with server-side payment method
      payment_method_id = params[:payment_method_id]
      begin
        StripeService.create_payment_intent(invoice: @invoice, payment_method_id: payment_method_id)
        redirect_to tenant_invoice_path(@invoice), notice: 'Payment submitted successfully.'
      rescue ArgumentError => e
        if e.message.include?("Payment amount must be at least")
          flash[:alert] = "This invoice amount is too small for online payment. Please contact the business directly."
          redirect_to tenant_invoice_path(@invoice)
          return
        else
          raise e
        end
      rescue Stripe::StripeError => e
        flash.now[:alert] = e.message
        creds = Rails.application.credentials.stripe || {}
        @stripe_publishable_key = creds[:publishable_key] || ENV['STRIPE_PUBLISHABLE_KEY']
        render :new, status: :unprocessable_entity
      end
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

    def set_stripe_publishable_key
      creds = Rails.application.credentials.stripe || {}
      @stripe_publishable_key = creds[:publishable_key] || ENV['STRIPE_PUBLISHABLE_KEY']
    end

    # Helper to find the TenantCustomer record for the current user in this tenant
    # def current_tenant_customer
    #   @tenant_customer
    # end
  end
end 