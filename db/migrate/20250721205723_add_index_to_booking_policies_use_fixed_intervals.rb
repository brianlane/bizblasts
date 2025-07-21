class AddIndexToBookingPoliciesUseFixedIntervals < ActiveRecord::Migration[8.0]
  def change
    add_index :booking_policies, :use_fixed_intervals, name: 'index_booking_policies_on_use_fixed_intervals'
  end
end
