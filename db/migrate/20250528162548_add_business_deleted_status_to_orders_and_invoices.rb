class AddBusinessDeletedStatusToOrdersAndInvoices < ActiveRecord::Migration[8.0]
  def up
    # No database schema changes needed for adding enum values in Rails
    # The new business_deleted status is handled in the model enum definitions:
    # - Orders: business_deleted status (string value 'business_deleted')
    # - Invoices: business_deleted status (integer value 5)
    # This migration serves as documentation of the change
  end

  def down
    # Convert any business_deleted orders/invoices to cancelled if rolling back
    execute <<-SQL
      UPDATE orders SET status = 'cancelled' WHERE status = 'business_deleted';
      UPDATE invoices SET status = 4 WHERE status = 5;
    SQL
  end
end
