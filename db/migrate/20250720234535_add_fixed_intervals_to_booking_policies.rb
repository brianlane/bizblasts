class AddFixedIntervalsToBookingPolicies < ActiveRecord::Migration[8.0]
  def change
    add_column :booking_policies, :use_fixed_intervals, :boolean, default: false, null: false
    add_column :booking_policies, :interval_mins, :integer, default: 30
  end
end
