class AllowNullBusinessIdForOrphanedRecords < ActiveRecord::Migration[8.0]
  def up
    # Allow business_id to be null for orphaned records
    # This enables the orphaning strategy during business deletion
    
    # Remove NOT NULL constraint from business_id in invoices
    change_column_null :invoices, :business_id, true
    
    # Remove NOT NULL constraint from business_id in orders  
    change_column_null :orders, :business_id, true
    
    # Remove NOT NULL constraint from business_id in bookings
    change_column_null :bookings, :business_id, true
    
    # Remove NOT NULL constraint from business_id in payments
    change_column_null :payments, :business_id, true
  end

  def down
    # Note: This rollback will fail if there are any orphaned records with null business_id
    # You would need to clean up orphaned records first before rolling back
    
    # Restore NOT NULL constraint (will fail if orphaned records exist)
    change_column_null :payments, :business_id, false
    change_column_null :bookings, :business_id, false
    change_column_null :orders, :business_id, false
    change_column_null :invoices, :business_id, false
  end
end
