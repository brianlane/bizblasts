module BusinessManager
  class OrdersController < BusinessManager::BaseController
    before_action :set_order, only: [:show, :edit, :update, :refund]
    before_action :load_collections, only: [:new, :edit, :create, :update]

    def index
      # Redirect to the new unified transactions view
      redirect_to business_manager_transactions_path(filter: 'orders', status: params[:status], type: params[:type])
    end

    def show
      # @order is already set by set_order before_action with proper eager loading
    end

    def new
      @order = @current_business.orders.new
      @order.build_tenant_customer
      # No initial product line items; start with zero rows so user must click 'Add Product'
    end

    def create
      # Only build nested customer if creating a new one; remove when selecting existing
      cp = order_params.to_h.with_indifferent_access
      if cp[:tenant_customer_id].present? && cp[:tenant_customer_id] != 'new'
        cp.delete(:tenant_customer_attributes)
      elsif cp[:tenant_customer_id] == 'new'
        # Remove placeholder and use nested attributes for new customer
        cp.delete(:tenant_customer_id)
      end
      # Determine order_type based on submitted line_items_attributes
      line_items_attrs = cp['line_items_attributes'] || {}
      filtered = line_items_attrs.values.reject { |attrs| attrs['_destroy'].to_s == 'true' }
      types = filtered.map { |attrs| attrs['service_id'].present? ? :service : :product }.uniq
      order_type = if types.include?(:service) && types.include?(:product)
                     'mixed'
                   elsif types.include?(:service)
                     'service'
                   else
                     'product'
                   end
      @order = @current_business.orders.new(cp.merge(order_type: order_type))
      if @order.save
        # Provide feedback about invoice creation for service orders
        if @order.order_type_service? || @order.order_type_mixed?
          if @order.invoice.present?
            redirect_to business_manager_order_path(@order), notice: 'Order created successfully. Invoice has been generated and emailed to the customer.'
          else
            redirect_to business_manager_order_path(@order), notice: 'Order created successfully. Note: Invoice creation may have failed - please check logs.'
          end
        else
          redirect_to business_manager_order_path(@order), notice: 'Order created successfully'
        end
      else
        flash.now[:alert] = "Unable to create order: #{@order.errors.full_messages.to_sentence}"
        render :new
      end
    end

    def edit
    end

    def update
      # Only update nested customer when creating a new one
      cp = order_params.to_h.with_indifferent_access
      if cp[:tenant_customer_id].present? && cp[:tenant_customer_id] != 'new'
        cp.delete(:tenant_customer_attributes)
      elsif cp[:tenant_customer_id] == 'new'
        cp.delete(:tenant_customer_id)
      end
      # Determine order_type based on submitted line_items_attributes
      line_items_attrs = cp['line_items_attributes'] || {}
      filtered = line_items_attrs.values.reject { |attrs| attrs['_destroy'].to_s == 'true' }
      types = filtered.map { |attrs| attrs['service_id'].present? ? :service : :product }.uniq
      order_type = if types.include?(:service) && types.include?(:product)
                     'mixed'
                   elsif types.include?(:service)
                     'service'
                   else
                     'product'
                   end
      if @order.update(cp.merge(order_type: order_type))
        # Check if we need to create an invoice for newly changed service/mixed orders
        if (@order.order_type_service? || @order.order_type_mixed?) && @order.invoice.blank?
          # Manually trigger invoice creation for updated orders
          @order.send(:create_invoice_for_service_orders)
        end
        
        # Provide appropriate feedback
        if (@order.order_type_service? || @order.order_type_mixed?) && @order.invoice.present?
          redirect_to business_manager_order_path(@order), notice: 'Order updated successfully. Invoice has been generated and emailed to the customer.'
        else
          redirect_to business_manager_order_path(@order), notice: 'Order updated successfully'
        end
      else
        flash.now[:alert] = "Unable to update order: #{@order.errors.full_messages.to_sentence}"
        render :edit
      end
    end

    # PATCH /manage/orders/:id/refund
    def refund
      if @order.status_refunded?
        redirect_to business_manager_order_path(@order), notice: 'Order already refunded.'
        return
      end

      invoice = @order.invoice
      if invoice.blank? || invoice.payments.successful.none?
        redirect_to business_manager_order_path(@order), alert: 'No completed payments found to refund.'
        return
      end

      refund_failures = []
      invoice.payments.successful.each do |payment|
        success = payment.initiate_refund(reason: 'requested_by_customer', user: current_user)
        refund_failures << payment.id unless success
      end

      if refund_failures.empty?
        # Use helper method to check if all payments are refunded and update order status accordingly
        @order.check_and_update_refund_status!
        redirect_to business_manager_order_path(@order), notice: 'Refund initiated successfully.'
      else
        redirect_to business_manager_order_path(@order), alert: "Refund failed for payments: #{refund_failures.join(', ')}"
      end
    end

    private

    def set_order
      @order = @current_business.orders.includes(
                 :tenant_customer, 
                 :shipping_method, 
                 :tax_rate,
                 :invoice,
                 line_items: { product_variant: :product }
               ).find(params[:id])
    end

    def load_collections
      @customers = @current_business.tenant_customers.active
      @shipping_methods = @current_business.shipping_methods.active
      @tax_rates = @current_business.tax_rates
      @product_variants = @current_business.products.includes(:product_variants).flat_map(&:product_variants)
      @services = @current_business.services
      @staff_members = @current_business.staff_members
    end

    def order_params
      params.require(:order).permit(
        :tenant_customer_id, :shipping_method_id, :tax_rate_id,
        :shipping_address, :billing_address, :notes, :order_type,
        tenant_customer_attributes: [:first_name, :last_name, :email, :phone],
        line_items_attributes: [:id, :product_variant_id, :service_id, :staff_member_id, :quantity, :price, :total_amount, :_destroy]
      )
    end
  end
end 