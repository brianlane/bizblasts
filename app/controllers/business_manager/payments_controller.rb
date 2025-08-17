# frozen_string_literal: true

module BusinessManager
  class PaymentsController < BusinessManager::BaseController
    before_action :set_payment, only: [:show]
    before_action :set_customers, only: [:new, :create]
    
    helper_method :stripe_dashboard_payments_url

    # GET /manage/payments
    def index
      authorize Payment
      
      # Get actual payments
      @payments = @current_business.payments.includes(:invoice, :order, :tenant_customer)
                                           .order(created_at: :desc)

      # Get pending invoices without payments (like QR payments awaiting payment)
      @pending_invoices = @current_business.invoices
                                          .joins(:order)
                                          .where(status: :pending)
                                          .where.not(id: @current_business.payments.select(:invoice_id).where.not(invoice_id: nil))
                                          .includes(:tenant_customer, :order)
                                          .order(created_at: :desc)

      # Combine payments and pending invoices for display
      @payment_items = []
      
      # Add actual payments
      @payments.each do |payment|
        @payment_items << {
          type: :payment,
          item: payment,
          id: "payment_#{payment.id}",
          customer: payment.tenant_customer,
          amount: payment.amount,
          status: payment.status,
          method: payment.payment_method,
          date: payment.created_at
        }
      end
      
      # Add pending invoices
      @pending_invoices.each do |invoice|
        @payment_items << {
          type: :pending_invoice,
          item: invoice,
          id: "invoice_#{invoice.id}",
          customer: invoice.tenant_customer,
          amount: invoice.total_amount,
          status: :pending,
          method: 'pending',
          date: invoice.created_at
        }
      end
      
      # Sort by date and paginate
      @payment_items.sort_by! { |item| item[:date] }.reverse!
      
      # Apply status filter
      if params[:status].present? && (Payment.statuses.key?(params[:status]) || params[:status] == 'pending')
        if params[:status] == 'pending'
          @payment_items.select! { |item| item[:status] == :pending || item[:status] == 'pending' }
        else
          @payment_items.select! { |item| item[:status].to_s == params[:status] }
        end
      end

      # Apply date filter
      if params[:date_range].present?
        date_range = case params[:date_range]
        when 'today'
          Date.current.beginning_of_day..Date.current.end_of_day
        when 'week'
          1.week.ago.beginning_of_day..Date.current.end_of_day
        when 'month'
          1.month.ago.beginning_of_day..Date.current.end_of_day
        when 'custom'
          if params[:start_date].present? && params[:end_date].present?
            Date.parse(params[:start_date]).beginning_of_day..Date.parse(params[:end_date]).end_of_day
          end
        end
        
        if date_range
          @payment_items.select! { |item| date_range.cover?(item[:date]) }
        end
      end
      
      # Paginate the combined results
      @payment_items = Kaminari.paginate_array(@payment_items).page(params[:page]).per(25)

      # Calculate summary stats
      @payment_stats = {
        total_payments: @current_business.payments.count + @pending_invoices.count,
        successful_payments: @current_business.payments.completed.count,
        total_amount: @current_business.payments.completed.sum(:amount),
        pending_amount: @current_business.payments.pending.sum(:amount) + @pending_invoices.sum(:total_amount),
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

    # GET /manage/payment/new
    def new
      @order = current_business.orders.build
      @order.tenant_customer = current_business.tenant_customers.build
    end
    
    # Handle any requests to /manage/payment (without /new) - redirect to new
    def show
      redirect_to new_business_manager_payment_path
    end
    
    # POST /manage/payment
    def create
      # Server-side validation
      if params[:tenant_customer_id].blank? || params[:tenant_customer_id] == ''
        set_customers
        flash.now[:error] = 'Please select a customer or create a new customer.'
        render :new, status: :unprocessable_entity
        return
      end
      
      payment_amount = params[:payment_amount].to_f
      if payment_amount < 0.50
        set_customers
        flash.now[:error] = 'Payment amount must be at least $0.50.'
        render :new, status: :unprocessable_entity
        return
      end
      
      @order = current_business.orders.build(payment_order_params)
      @order.order_type = 'service'  # Set as service type for payment collection
      @order.status = 'pending_payment'
      
      # Skip total calculation to allow custom amount
      @order.skip_total_calculation = true
      
      # Handle customer selection or creation
      if params[:tenant_customer_id] != 'new'
        begin
          @order.tenant_customer = current_business.tenant_customers.find(params[:tenant_customer_id])
        rescue ActiveRecord::RecordNotFound
          set_customers
          flash.now[:error] = 'Selected customer not found. Please select a valid customer.'
          render :new, status: :unprocessable_entity
          return
        end
      else
        # Create new customer - validate required fields
        customer_params = params[:tenant_customer]&.permit(:first_name, :last_name, :email, :phone) || {}
        
        if customer_params[:first_name].blank?
          set_customers
          flash.now[:error] = 'Please enter the customer\'s first name.'
          render :new, status: :unprocessable_entity
          return
        end
        
        if customer_params[:last_name].blank?
          set_customers
          flash.now[:error] = 'Please enter the customer\'s last name.'
          render :new, status: :unprocessable_entity
          return
        end
        
        if customer_params[:email].blank?
          set_customers
          flash.now[:error] = 'Please enter the customer\'s email address.'
          render :new, status: :unprocessable_entity
          return
        end
        
        @order.tenant_customer = current_business.tenant_customers.build(customer_params)
      end
      
      # Set custom total amount directly (bypass line item calculations)
      @order.total_amount = payment_amount
      
      # Skip normal total calculations by setting other amounts to 0
      @order.tax_amount = 0
      @order.shipping_amount = 0
      
      # Add description for payment collection
      @order.notes = "Payment Collection: $#{sprintf('%.2f', payment_amount)}"
      
      if @order.save
        # Reload to ensure invoice is available
        @order.reload
        
        # Create QR code for immediate payment collection
        begin
          if @order.invoice.present?
            @qr_data = QrPaymentService.generate_qr_code(@order.invoice)
            render :show_qr
          else
            redirect_to business_manager_order_path(@order), notice: 'Payment order created successfully. Invoice is being generated...'
          end
        rescue => e
          Rails.logger.error "[PAYMENT_COLLECTION] Error generating QR code for order #{@order.order_number}: #{e.message}"
          redirect_to business_manager_order_path(@order), notice: 'Payment order created successfully. Unable to generate QR code at this time.'
        end
      else
        set_customers
        flash.now[:error] = 'Unable to create payment order. Please check your information and try again.'
        render :new, status: :unprocessable_entity
      end
    end

    private

    def set_payment
      @payment = @current_business.payments.includes(:invoice, :order, :tenant_customer).find(params[:id])
    rescue ActiveRecord::RecordNotFound
      redirect_to business_manager_payments_path, alert: 'Payment not found.'
    end

    def set_customers
      @customers = current_business.tenant_customers.order(:first_name, :last_name)
    end
    
    def payment_order_params
      params.permit(:notes)
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