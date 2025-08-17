# frozen_string_literal: true

class BusinessManager::InvoicesController < BusinessManager::BaseController
  before_action :set_invoice, only: [:show, :resend, :cancel, :qr_payment, :payment_status, :mark_as_paid]

  # POST /manage/invoices/:id/resend
  def resend
    authorize @invoice
    InvoiceMailer.invoice_created(@invoice).deliver_later
    redirect_to business_manager_invoice_path(@invoice), notice: 'Invoice resent to customer.'
  end

  # PATCH /manage/invoices/:id/cancel
  def cancel
    authorize @invoice
    if @invoice.cancelled?
      redirect_to business_manager_invoice_path(@invoice), notice: 'Invoice already cancelled.'
    else
      @invoice.update!(status: :cancelled)
      redirect_to business_manager_invoice_path(@invoice), notice: 'Invoice cancelled.'
    end
  end

  # PATCH /manage/invoices/:id/mark_as_paid
  def mark_as_paid
    authorize @invoice
    
    if @invoice.paid?
      redirect_to business_manager_invoice_path(@invoice), notice: 'Invoice is already paid.'
      return
    end
    
    begin
      # Create a payment record to track this manual payment
      payment = @invoice.payments.create!(
        business: @current_business,
        tenant_customer: @invoice.tenant_customer,
        amount: @invoice.total_amount,
        status: :completed,
        payment_method: :other, # Manual payment outside system
        paid_at: Time.current,
        platform_fee_amount: 0.0, # No platform fees for manual payments
        stripe_fee_amount: 0.0,   # No Stripe fees for manual payments
        business_amount: @invoice.total_amount # Full amount goes to business
      )
      
      # Mark invoice as paid
      @invoice.mark_as_paid!
      
      # Update order status if applicable (mirroring StripeService logic)
      if (order = @invoice.order)
        # For product or experience orders, mark as paid; for services, mark as processing
        new_status = order.payment_required? ? :paid : :processing
        order.update!(status: new_status)
        
        # Check if order should be completed (for service orders without bookings)
        order.complete_if_ready!
      else
        # No associated order – this is a standalone invoice payment. Send confirmation email.
        begin
          InvoiceMailer.payment_confirmation(@invoice, payment).deliver_later
          Rails.logger.info "[EMAIL] Sent payment confirmation email for manually paid Invoice ##{@invoice.invoice_number}"
        rescue => e
          Rails.logger.error "[EMAIL] Failed to send payment confirmation email for Invoice ##{@invoice.invoice_number}: #{e.message}"
        end
      end
      
      Rails.logger.info "[MANUAL_PAYMENT] Invoice #{@invoice.invoice_number} marked as paid manually by business manager"
      redirect_to business_manager_invoice_path(@invoice), notice: 'Invoice marked as paid successfully.'
      
    rescue => e
      Rails.logger.error "[MANUAL_PAYMENT] Failed to mark invoice #{@invoice.invoice_number} as paid: #{e.message}"
      redirect_to business_manager_invoice_path(@invoice), alert: 'Failed to mark invoice as paid. Please try again.'
    end
  end

  # GET /manage/invoices
  def index
    @invoices = @current_business.invoices.order(created_at: :desc).page(params[:page]).per(10)
    authorize Invoice
  end

  # GET /manage/invoices/:id
  def show
    authorize @invoice
  end

  # GET /manage/invoices/:id/qr_payment
  def qr_payment
    authorize @invoice
    
    begin
      @qr_data = QrPaymentService.generate_qr_code(@invoice)
      render layout: false
    rescue => e
      Rails.logger.error "[QR_PAYMENT] Error generating QR code: #{e.message}"
      @qr_data = nil
      render layout: false
    end
  end

  # GET /manage/invoices/:id/payment_status
  def payment_status
    authorize @invoice
    
    status_data = QrPaymentService.check_payment_status(@invoice)
    render json: status_data
  end

  private

  def set_invoice
    @invoice = @current_business.invoices.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to business_manager_invoices_path, alert: 'Invoice not found.'
  end
end 