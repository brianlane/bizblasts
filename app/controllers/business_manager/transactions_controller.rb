module BusinessManager
  class TransactionsController < BusinessManager::BaseController
    before_action :set_transaction, only: [:show]

    def index
      @filter = params[:filter] || 'orders' # Default to showing orders like current behavior
      @transactions = []
      
      # Get orders if needed
      orders = []
      if @filter == 'orders' || @filter == 'both'
        orders = @current_business.orders.includes(
                   :tenant_customer, 
                   :shipping_method, 
                   :tax_rate,
                   :invoice,
                   line_items: { product_variant: :product }
                 )
        
        # Apply existing order filters
        if params[:status].present?
          @status_filter = params[:status]
          orders = orders.where(status: @status_filter)
        end
        
        if params[:type].present? && Order.order_types.key?(params[:type])
          @type_filter = params[:type]
          orders = orders.where(order_type: Order.order_types[@type_filter])
        end
      end
      
      # Get invoices if needed
      invoices = []
      if @filter == 'invoices' || @filter == 'both'
        invoices = @current_business.invoices.includes(
                     :tenant_customer,
                     booking: [:service, :booking_product_add_ons],
                     order: [:line_items]
                   )
        
        # Apply invoice-specific filters if needed
        if params[:invoice_status].present?
          @invoice_status_filter = params[:invoice_status]
          invoices = invoices.where(status: @invoice_status_filter)
        end
      end
      
      # Combine and sort by most recent
      @transactions = (orders.to_a + invoices.to_a).sort_by(&:created_at).reverse
      
      # Keep separate collections for dashboard stats (preserve existing functionality)
      @orders = @current_business.orders.includes(
                  :tenant_customer, 
                  :shipping_method, 
                  :tax_rate,
                  :invoice,
                  line_items: { product_variant: :product }
                )
    end

    def show
      # Handle both orders and invoices
      if @transaction.is_a?(Order)
        redirect_to business_manager_order_path(@transaction)
      elsif @transaction.is_a?(Invoice)
        redirect_to business_manager_invoice_path(@transaction)
      else
        redirect_to business_manager_transactions_path, alert: 'Transaction not found.'
      end
    end

    private

    def set_transaction
      # Try to find as order first, then as invoice
      begin
        @transaction = @current_business.orders.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        begin
          @transaction = @current_business.invoices.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          redirect_to business_manager_transactions_path, alert: 'Transaction not found.'
        end
      end
    end
  end
end 