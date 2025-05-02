class InvoiceProductAdder
  def self.add(invoice, product_variant, quantity)
    ActiveRecord::Base.transaction do
      # Decrement stock and ensure rollback on failure
      unless product_variant.decrement_stock!(quantity)
        invoice.errors.add(:base, "Insufficient stock for #{product_variant.name}")
        raise ActiveRecord::Rollback
      end

      # Create and save the line item
      line_item = invoice.line_items.create(
        product_variant: product_variant,
        quantity: quantity
      )

      unless line_item.persisted?
        # Rollback on line item save failure
        raise ActiveRecord::Rollback
      end

      # Save invoice to update totals and propagate callbacks
      unless invoice.save
        raise ActiveRecord::Rollback
      end

      return line_item
    end

    false
  end
end 