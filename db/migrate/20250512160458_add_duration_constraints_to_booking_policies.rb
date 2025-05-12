class AddDurationConstraintsToBookingPolicies < ActiveRecord::Migration[8.0]
  def change
    add_column :booking_policies, :min_duration_mins, :integer
    add_column :booking_policies, :max_duration_mins, :integer
  end
end
