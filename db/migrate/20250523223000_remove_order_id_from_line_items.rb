class RemoveOrderIdFromLineItems < ActiveRecord::Migration[8.0]
  def up
    # Check if the order_id column exists before trying to remove it
    if column_exists?(:line_items, :order_id)
      remove_column :line_items, :order_id
    end
  end

  def down
    # This is potentially tricky to reverse reliably without knowing the original logic.
    # If a rollback is necessary, manual intervention might be required to recreate order_id
    # and populate it based on lineable_type = 'Order' and lineable_id.
    # For simplicity in the down migration, we'll add the column back nullable.
    unless column_exists?(:line_items, :order_id)
      add_column :line_items, :order_id, :bigint
      add_index :line_items, :order_id # Add back index if it existed
    end
  end
end 