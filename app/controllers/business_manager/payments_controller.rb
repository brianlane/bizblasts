# frozen_string_literal: true

module BusinessManager
  class PaymentsController < BusinessManager::BaseController
    before_action :set_payment, only: [:show]
    
    helper_method :stripe_dashboard_payments_url

    # GET /manage/payments
    def index
      authorize Payment
      @payments = @current_business.payments.includes(:invoice, :order, :tenant_customer)
                                           .order(created_at: :desc)
                                           .page(params[:page])
                                           .per(25)

      # Apply status filter
      if params[:status].present? && Payment.statuses.key?(params[:status])
        @payments = @payments.where(status: params[:status])
      end

      # Apply date filter
      if params[:date_range].present?
        case params[:date_range]
        when 'today'
          @payments = @payments.where(created_at: Date.current.beginning_of_day..Date.current.end_of_day)
        when 'week'
          @payments = @payments.where(created_at: 1.week.ago.beginning_of_day..Date.current.end_of_day)
        when 'month'
          @payments = @payments.where(created_at: 1.month.ago.beginning_of_day..Date.current.end_of_day)
        when 'custom'
          if params[:start_date].present? && params[:end_date].present?
            start_date = Date.parse(params[:start_date]).beginning_of_day
            end_date = Date.parse(params[:end_date]).end_of_day
            @payments = @payments.where(created_at: start_date..end_date)
          end
        end
      end

      # Calculate summary stats
      @payment_stats = {
        total_payments: @current_business.payments.count,
        successful_payments: @current_business.payments.completed.count,
        total_amount: @current_business.payments.completed.sum(:amount),
        pending_amount: @current_business.payments.pending.sum(:amount),
        refunded_amount: @current_business.payments.refunded.sum(:amount)
      }
    end

    # GET /manage/payments/:id
    def show
      authorize @payment
      # @payment is set by before_action
      
      # Get related Stripe data if available
      @stripe_payment_intent = nil
      @stripe_charge = nil
      @stripe_dashboard_url = nil
      
      if @payment.stripe_payment_intent_id.present? && @current_business.stripe_account_id.present?
        @stripe_dashboard_url = stripe_dashboard_payment_url
      end
    end

    private

    def set_payment
      @payment = @current_business.payments.includes(:invoice, :order, :tenant_customer).find(params[:id])
    rescue ActiveRecord::RecordNotFound
      redirect_to business_manager_payments_path, alert: 'Payment not found.'
    end

    def stripe_dashboard_payment_url
      # Generate URL to Stripe Dashboard for this specific payment
      if @payment.stripe_payment_intent_id.present?
        if Rails.env.production?
          "https://dashboard.stripe.com/#{@current_business.stripe_account_id}/payments/#{@payment.stripe_payment_intent_id}"
        else
          "https://dashboard.stripe.com/test/#{@current_business.stripe_account_id}/payments/#{@payment.stripe_payment_intent_id}"
        end
      end
    end

    def stripe_dashboard_payments_url
      # Generate URL to Stripe Dashboard payments list
      if @current_business.stripe_account_id.present?
        if Rails.env.production?
          "https://dashboard.stripe.com/#{@current_business.stripe_account_id}/payments"
        else
          "https://dashboard.stripe.com/test/#{@current_business.stripe_account_id}/payments"
        end
      end
    end
  end
end 