class FixLineItemsStaffMemberConstraint < ActiveRecord::Migration[8.0]
  def up
    # Check if staff_member_id is already nullable
    column = columns(:line_items).find { |c| c.name == 'staff_member_id' }
    
    # Make staff_member_id nullable if it isn't already
    if column && !column.null
      change_column_null :line_items, :staff_member_id, true
    end
    
    # Check if the foreign key exists and has the correct constraint
    if foreign_key_exists?(:line_items, :staff_members)
      fk = foreign_keys(:line_items).find { |fk| fk.to_table == 'staff_members' }
      
      # Only modify if it doesn't already have nullify
      if fk && fk.options[:on_delete] != :nullify
        # Remove the existing foreign key constraint
        remove_foreign_key :line_items, :staff_members
        
        # Add the foreign key constraint with on_delete: :nullify
        add_foreign_key :line_items, :staff_members, on_delete: :nullify
      end
    else
      # If no foreign key exists, add one with nullify
      add_foreign_key :line_items, :staff_members, on_delete: :nullify
    end
  end

  def down
    # Check if the foreign key exists before trying to modify it
    if foreign_key_exists?(:line_items, :staff_members)
      # Remove the updated foreign key constraint
      remove_foreign_key :line_items, :staff_members
      
      # Restore the original foreign key constraint (without on_delete)
      add_foreign_key :line_items, :staff_members
    end
    
    # Check if staff_member_id is currently nullable
    column = columns(:line_items).find { |c| c.name == 'staff_member_id' }
    
    # Only change if it's currently nullable and there are no null values
    if column && column.null
      # Make staff_member_id not nullable again (this might fail if there are null values)
      change_column_null :line_items, :staff_member_id, false
    end
  end
end
