class AddMinAdvanceMinsToBookingPolicies < ActiveRecord::Migration[8.0]
  def change
    add_column :booking_policies, :min_advance_mins, :integer, default: 0
    add_index :booking_policies, :min_advance_mins
  end
end
