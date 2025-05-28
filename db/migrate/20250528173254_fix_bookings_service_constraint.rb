class FixBookingsServiceConstraint < ActiveRecord::Migration[8.0]
  def up
    # Check if the foreign key exists before trying to remove it
    if foreign_key_exists?(:bookings, :services)
      # Get the current foreign key to check if it already has nullify
      fk = foreign_keys(:bookings).find { |fk| fk.to_table == 'services' }
      
      # Only modify if it doesn't already have nullify
      if fk && fk.options[:on_delete] != :nullify
        # Remove the existing foreign key constraint
        remove_foreign_key :bookings, :services
        
        # Add it back with nullify (we want to preserve booking history)
        add_foreign_key :bookings, :services, on_delete: :nullify
      end
    else
      # If no foreign key exists, add one with nullify
      add_foreign_key :bookings, :services, on_delete: :nullify
    end
  end

  def down
    # Check if the foreign key exists before trying to modify it
    if foreign_key_exists?(:bookings, :services)
      # Remove the nullify constraint and restore the original
      remove_foreign_key :bookings, :services
      add_foreign_key :bookings, :services
    end
  end
end
