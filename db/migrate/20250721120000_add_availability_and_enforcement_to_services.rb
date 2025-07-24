class AddAvailabilityAndEnforcementToServices < ActiveRecord::Migration[8.0]
  def change
    add_column :services, :availability, :jsonb, default: {}, null: false
    add_column :services, :enforce_service_availability, :boolean, default: true, null: false
  end
end 