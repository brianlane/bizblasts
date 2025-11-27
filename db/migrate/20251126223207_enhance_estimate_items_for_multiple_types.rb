class EnhanceEstimateItemsForMultipleTypes < ActiveRecord::Migration[8.0]
  def change
    # Add polymorphic reference for products
    add_reference :estimate_items, :product, null: true, foreign_key: true
    add_reference :estimate_items, :product_variant, null: true, foreign_key: true

    # Add item type enum (0: service, 1: product, 2: labor, 3: part, 4: misc)
    add_column :estimate_items, :item_type, :integer, default: 0, null: false

    # Add optional flag and customer selection tracking
    add_column :estimate_items, :optional, :boolean, default: false, null: false
    add_column :estimate_items, :customer_selected, :boolean, default: true, null: false
    add_column :estimate_items, :customer_declined, :boolean, default: false, null: false

    # Add labor-specific fields
    add_column :estimate_items, :hours, :decimal, precision: 10, scale: 2
    add_column :estimate_items, :hourly_rate, :decimal, precision: 10, scale: 2

    # Add position for ordering
    add_column :estimate_items, :position, :integer, default: 0, null: false

    # Add index for performance
    add_index :estimate_items, [:estimate_id, :position]
    add_index :estimate_items, :item_type
    add_index :estimate_items, [:estimate_id, :optional]
  end
end
