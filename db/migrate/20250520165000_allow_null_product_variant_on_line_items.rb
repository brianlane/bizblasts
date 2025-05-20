class AllowNullProductVariantOnLineItems < ActiveRecord::Migration[8.0]
  def up
    # Check if the column exists before modifying it
    if column_exists?(:line_items, :product_variant_id)
      change_column_null :line_items, :product_variant_id, true
    else
      # Column doesn't exist in production, so we need to add it
      add_reference :line_items, :product_variant, foreign_key: true, type: :bigint, null: true
    end
  end

  def down
    # Only make it not null if it exists
    if column_exists?(:line_items, :product_variant_id)
      change_column_null :line_items, :product_variant_id, false
    end
  end
end 