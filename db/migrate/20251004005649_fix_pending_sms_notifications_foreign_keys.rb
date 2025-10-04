class FixPendingSmsNotificationsForeignKeys < ActiveRecord::Migration[8.0]
  def up
    # Remove existing foreign key constraints for business and tenant_customer
    remove_foreign_key :pending_sms_notifications, :businesses
    remove_foreign_key :pending_sms_notifications, :tenant_customers

    # Add foreign key constraints with cascade deletion
    # When business is deleted, all its pending notifications should be deleted
    add_foreign_key :pending_sms_notifications, :businesses, on_delete: :cascade

    # When tenant_customer is deleted, all their pending notifications should be deleted
    add_foreign_key :pending_sms_notifications, :tenant_customers, on_delete: :cascade

    # Note: Keep booking, invoice, order foreign keys as-is (restrict)
    # We want to preserve notifications even if specific bookings/invoices/orders are deleted
  end

  def down
    # Remove cascade foreign keys
    remove_foreign_key :pending_sms_notifications, :businesses
    remove_foreign_key :pending_sms_notifications, :tenant_customers

    # Restore original restrict foreign keys
    add_foreign_key :pending_sms_notifications, :businesses
    add_foreign_key :pending_sms_notifications, :tenant_customers
  end
end
