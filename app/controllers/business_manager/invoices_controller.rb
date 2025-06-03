# frozen_string_literal: true

class BusinessManager::InvoicesController < BusinessManager::BaseController
  before_action :set_invoice, only: [:show, :resend]

  # POST /manage/invoices/:id/resend
  def resend
    authorize @invoice
    InvoiceMailer.invoice_created(@invoice).deliver_later
    redirect_to business_manager_invoice_path(@invoice), notice: 'Invoice resent to customer.'
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

  private

  def set_invoice
    @invoice = @current_business.invoices.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to business_manager_invoices_path, alert: 'Invoice not found.'
  end
end 