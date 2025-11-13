class AddServiceRadiusToBookingPolicies < ActiveRecord::Migration[7.1]
  def change
    add_column :booking_policies, :service_radius_enabled, :boolean, default: false, null: false
    add_column :booking_policies, :service_radius_miles, :integer, default: 50, null: false
  end
end

