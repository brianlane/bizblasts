class OrderCreator
    def self.create(order_params)
      # Clone the params to avoid modifying the input
      params = order_params.dup
      
      # Extract line items from params for separate handling
      line_items_params = params.delete(:line_items_attributes) || []
      
      # Build the order
      order = Order.new(params)
      order.business ||= TenantCustomer.find(params[:tenant_customer_id]).business if params[:tenant_customer_id].present?
      
      # Early return if basic order parameters are invalid
      unless order.valid?
        return order
      end
      
      # Use a transaction for the entire process
      ActiveRecord::Base.transaction do
        # First, save the order without line items
        if !order.save
          return order # Will rollback due to transaction block
        end
        
        # Now that the order has an ID, create line items
        line_items_params.each do |line_item_params|
          # Create line items directly rather than building and saving
          line_item = order.line_items.create(line_item_params)
          
          if !line_item.persisted?
            # If line item creation fails, add errors to order and roll back
            line_item.errors.full_messages.each do |message|
              order.errors.add(:base, "Line item error: #{message}")
            end
            raise ActiveRecord::Rollback
          end
          
          # Decrement stock after successful line item creation
          variant = line_item.product_variant # Assuming product_variant is loaded/accessible
          quantity = line_item.quantity
          unless variant.decrement_stock!(quantity)
            order.errors.add(:base, "Insufficient stock for #{variant.name}")
            raise ActiveRecord::Rollback # Rollback if stock update fails
          end
        end
      end
      
      # Reload to ensure we have updated state
      order.reload if order.persisted?
      
      # Return the order - will be persisted if successful
      order
    end
  end