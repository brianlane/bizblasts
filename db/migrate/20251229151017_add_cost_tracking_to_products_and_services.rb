class AddCostTrackingToProductsAndServices < ActiveRecord::Migration[8.1]
  def change
    # Add cost tracking to products
    add_column :products, :cost_price, :decimal, precision: 10, scale: 2

    # Add cost tracking to product variants
    add_column :product_variants, :cost_price, :decimal, precision: 10, scale: 2

    # Add cost tracking to services
    add_column :services, :cost_price, :decimal, precision: 10, scale: 2

    # Add cost tracking to service variants
    add_column :service_variants, :cost_price, :decimal, precision: 10, scale: 2
  end
end
