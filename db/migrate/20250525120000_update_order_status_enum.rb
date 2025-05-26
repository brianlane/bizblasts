class UpdateOrderStatusEnum < ActiveRecord::Migration[8.0]
  def up
    # Migrate old statuses to new enum values
    execute <<~SQL
      UPDATE orders SET status = 'pending_payment' WHERE status = 'pending';
    SQL
    execute <<~SQL
      UPDATE orders SET status = 'processing' WHERE status = 'completed';
    SQL

    # Change default status to pending_payment
    change_column_default :orders, :status, 'pending_payment'

    # Add check constraint for allowed statuses
    valid = %w[pending_payment paid cancelled shipped refunded processing].map { |s| "'#{s}'" }.join(',')
    execute <<~SQL
      ALTER TABLE orders
        ADD CONSTRAINT status_enum_check
          CHECK (status IN (#{valid}));
    SQL
  end

  def down
    # Remove check constraint
    execute <<~SQL
      ALTER TABLE orders
        DROP CONSTRAINT IF EXISTS status_enum_check;
    SQL

    # Revert default back to pending
    change_column_default :orders, :status, 'pending'

    # Migrate new statuses back to old values
    execute <<~SQL
      UPDATE orders SET status = 'pending' WHERE status = 'pending_payment';
    SQL
    execute <<~SQL
      UPDATE orders SET status = 'completed' WHERE status = 'processing';
    SQL
  end
end 