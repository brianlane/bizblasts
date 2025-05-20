class AllowNullProductVariantOnLineItems < ActiveRecord::Migration[8.0]
  def change
    # Make product_variant_id nullable for service line items
    change_column_null :line_items, :product_variant_id, true
  end
end 