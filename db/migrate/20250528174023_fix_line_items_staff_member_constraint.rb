class FixLineItemsStaffMemberConstraint < ActiveRecord::Migration[8.0]
  def up
    # Remove the existing foreign key constraint
    remove_foreign_key :line_items, :staff_members
    
    # Make staff_member_id nullable for orphaned line items
    change_column_null :line_items, :staff_member_id, true
    
    # Add the foreign key constraint with on_delete: :nullify
    add_foreign_key :line_items, :staff_members, on_delete: :nullify
  end

  def down
    # Remove the updated foreign key constraint
    remove_foreign_key :line_items, :staff_members
    
    # Make staff_member_id not nullable again (this might fail if there are null values)
    change_column_null :line_items, :staff_member_id, false
    
    # Restore the original foreign key constraint (without on_delete)
    add_foreign_key :line_items, :staff_members
  end
end
