class AddAvailabilityToStaffMembers < ActiveRecord::Migration[8.0]
  def change
    add_column :staff_members, :availability, :jsonb, default: {}, null: false
  end
end
