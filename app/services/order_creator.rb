class OrderCreator
    def self.create(order_params)
      # Convert parameters to a plain Hash for mass assignment
      params = order_params.respond_to?(:to_h) ? order_params.to_h : order_params.dup
      # Extract line items from params for separate handling
      line_items_params = params.delete('line_items_attributes') || params.delete(:line_items_attributes) || []
      
      # Build the order
      order = Order.new(params)
      # Explicitly set the default status before validation
      order.status = :pending
      
      order.business ||= TenantCustomer.find(params[:tenant_customer_id]).business if params[:tenant_customer_id].present?
      
      # Use a transaction for the entire process
      ActiveRecord::Base.transaction do
        # First, save the order without line items
        if !order.save
          return order # Will rollback due to transaction block
        end
        
        # Now that the order has an ID, create line items
        line_items_params.each do |line_item_params|
          # Create line items directly rather than building and saving
          line_item = order.line_items.create(line_item_params.to_h)
          
          if !line_item.persisted?
            # If line item creation fails, add errors to order and roll back
            line_item.errors.full_messages.each do |message|
              order.errors.add(:base, "Line item error: #{message}")
            end
            raise ActiveRecord::Rollback
          end
          
          # Use reserve_stock! instead of decrement_stock!
          variant = line_item.product_variant
          quantity = line_item.quantity
          unless variant.reserve_stock!(quantity, order)
            order.errors.add(:base, "Insufficient stock for #{variant.name}")
            raise ActiveRecord::Rollback
          end
        end

        # Recalculate and save order totals after line items and stock reservations are created
        order.calculate_totals!
        order.save!

      end
      
      if order.errors.any?
        # If there were any errors, clean up reservations
        order.stock_reservations.each do |reservation|
          reservation.product_variant.release_reservation!(reservation)
        end
      end
      
      # Reload to ensure we have updated state
      # Removed redundant reload here, as save! within the transaction updates the object.
      # order.reload if order.persisted?
      
      # Return the order - will be persisted if successful
      order
    end

    def self.build_from_cart(cart)
      order = Order.new
      # Explicitly set the default status
      order.status = :pending

      # Build line items in memory
      order.line_items.build(
        cart.map do |variant, quantity|
          {
            product_variant: variant,
            quantity: quantity,
            price: variant.final_price,
            total_amount: variant.final_price * quantity
          }
        end
      )
      order
    end

    def self.create_from_cart(cart, order_params)
      params = order_params.dup
      line_items_attributes = cart.map do |variant, quantity|
        {
          product_variant_id: variant.id,
          quantity: quantity,
          price: variant.final_price,
          total_amount: variant.final_price * quantity
        }
      end
      params[:line_items_attributes] = line_items_attributes
      create(params)
    end
  end