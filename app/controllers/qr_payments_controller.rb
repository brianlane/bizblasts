# frozen_string_literal: true

class QrPaymentsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_invoice, only: [:show, :status]
  
  # GET /invoices/:id/qr_payment
  def show
    # Ensure user can access this invoice
    authorize @invoice, :show?
    
    begin
      @qr_data = QrPaymentService.generate_qr_code(@invoice)
      
      respond_to do |format|
        format.json { render json: @qr_data }
        format.html { render partial: 'qr_payments/modal_content', locals: { qr_data: @qr_data } }
      end
    rescue => e
      Rails.logger.error "[QR_PAYMENT] Error generating QR code: #{e.message}"
      
      respond_to do |format|
        format.json { render json: { error: "Failed to generate QR code" }, status: :unprocessable_entity }
        format.html { render plain: "Error: Failed to generate QR code", status: :unprocessable_entity }
      end
    end
  end
  
  # GET /invoices/:id/payment_status
  def status
    # Ensure user can access this invoice
    authorize @invoice, :show?
    
    status_data = QrPaymentService.check_payment_status(@invoice)
    
    render json: status_data
  end
  
  private
  
  def set_invoice
    @invoice = current_business.invoices.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    respond_to do |format|
      format.json { render json: { error: "Invoice not found" }, status: :not_found }
      format.html { redirect_to manage_invoices_path, alert: "Invoice not found" }
    end
  end
end