class MigrateExistingOrders < ActiveRecord::Migration[7.0]
  def up
    Order.reset_column_information
    Order.find_each do |order|
      product_items = order.line_items.where(lineable_type: 'ProductVariant').exists?
      service_items = order.line_items.where(lineable_type: 'Service').exists?
      
      if product_items && service_items
        order.update(order_type: 'mixed')
      elsif product_items
        order.update(order_type: 'product')
      elsif service_items  
        order.update(order_type: 'service')
      end
    end
  end

  def down
    # No need to revert order_type, can be left as is
  end
end 