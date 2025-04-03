class RemoveClientDetailsFromAppointments < ActiveRecord::Migration[8.0]
  def change
    remove_column :appointments, :client_name, :string
    remove_column :appointments, :client_email, :string
    remove_column :appointments, :client_phone, :string
  end
end
