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

    def download_csv
      @filter = params[:filter] || 'orders'
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
          orders = orders.where(status: params[:status])
        end
        
        if params[:type].present? && Order.order_types.key?(params[:type])
          orders = orders.where(order_type: Order.order_types[params[:type]])
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
          invoices = invoices.where(status: params[:invoice_status])
        end
      end
      
      # Combine and sort by most recent
      @transactions = (orders.to_a + invoices.to_a).sort_by(&:created_at).reverse
      
      respond_to do |format|
        format.csv do
          csv_data = generate_transactions_csv(@transactions)
          send_data csv_data, 
                    filename: "transactions-#{@current_business.name.parameterize}-#{Date.current}.csv",
                    type: 'text/csv'
        end
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

    def generate_transactions_csv(transactions)
      require 'csv'
      
      CSV.generate(headers: true) do |csv|
        # Add headers
        csv << [
          'Transaction ID',
          'Type',
          'Date',
          'Customer Name',
          'Customer Email',
          'Status',
          'Subtotal',
          'Tax Amount',
          'Shipping Amount',
          'Total Amount',
          'Items'
        ]
        
        # Add transaction rows
        transactions.each do |transaction|
          if transaction.is_a?(Order)
            csv << [
              transaction.order_number,
              "Order (#{transaction.order_type.titleize})",
              transaction.created_at.strftime('%Y-%m-%d %H:%M:%S'),
              transaction.tenant_customer&.full_name || 'N/A',
              transaction.tenant_customer&.email || 'N/A',
              transaction.status.titleize,
              transaction.subtotal_amount,
              transaction.tax_amount || 0,
              transaction.shipping_amount || 0,
              transaction.total_amount,
              format_order_items(transaction)
            ]
          else # Invoice
            csv << [
              transaction.invoice_number,
              transaction.booking ? 'Booking Invoice' : (transaction.order ? 'Order Invoice' : 'Invoice'),
              transaction.created_at.strftime('%Y-%m-%d %H:%M:%S'),
              transaction.tenant_customer&.full_name || 'N/A',
              transaction.tenant_customer&.email || 'N/A',
              transaction.status.titleize,
              transaction.amount || 0,
              transaction.tax_amount || 0,
              0, # Invoices don't have shipping
              transaction.total_amount,
              format_invoice_items(transaction)
            ]
          end
        end
      end
    end

    def format_order_items(order)
      items = order.line_items.map do |item|
        if item.product_variant
          "#{item.product_variant.product.name} (#{item.product_variant.name}) x#{item.quantity}"
        elsif item.service
          "#{item.service.name} x#{item.quantity}"
        else
          "Unknown item x#{item.quantity}"
        end
      end
      items.join('; ')
    end

    def format_invoice_items(invoice)
      if invoice.booking
        items = [invoice.booking.service.name]
        if invoice.booking.booking_product_add_ons.any?
          add_ons = invoice.booking.booking_product_add_ons.map { |addon| addon.product_variant.name }
          items += add_ons
        end
        items.join('; ')
      elsif invoice.order
        format_order_items(invoice.order)
      elsif invoice.line_items.any?
        invoice.line_items.map { |item| "#{item.name} x#{item.quantity}" }.join('; ')
      else
        'Manual invoice'
      end
    end
  end
end 