class StockAlertService
  def self.check_and_notify(product)
    # Simple stock alert logic that works without additional database fields
    return unless product.respond_to?(:stock_quantity)
    
    # Use a simple threshold of 10% of initial stock or minimum of 5 units
    threshold = [product.stock_quantity * 0.1, 5].max.to_i
    
    if product.stock_quantity <= threshold
      Rails.logger.warn "[STOCK ALERT] Low stock for product #{product.id}: #{product.stock_quantity} remaining"
      
      # Could send email notifications here if needed
      # BusinessMailer.low_stock_alert(product).deliver_later
    end
  end
end 