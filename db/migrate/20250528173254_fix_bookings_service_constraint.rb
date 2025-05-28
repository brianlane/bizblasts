class FixBookingsServiceConstraint < ActiveRecord::Migration[8.0]
  def up
    # Remove the existing foreign key constraint that prevents deletion
    remove_foreign_key :bookings, :services
    
    # Add it back with nullify (we want to preserve booking history)
    # When service is deleted, we'll set service_id to null instead
    add_foreign_key :bookings, :services, on_delete: :nullify
  end

  def down
    # Restore the original constraint
    remove_foreign_key :bookings, :services
    add_foreign_key :bookings, :services
  end
end
