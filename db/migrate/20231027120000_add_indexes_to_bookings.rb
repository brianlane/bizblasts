class AddIndexesToBookings < ActiveRecord::Migration[7.1]
  def change
    # The indexes on staff_member_id and start_time already exist according to schema.rb.
    # Only adding the GIST index for time range overlap checks.

    # Add a GIST index on the time range for efficient overlap queries (requires btree_gist extension)
    # You might need to enable the extension in a previous migration or manually:
    # ENABLE EXTENSION btree_gist;
    add_index :bookings, [:start_time, :end_time], using: :gist
  end
end 