class CreateTenantCustomers < ActiveRecord::Migration[8.0]
  def change
    create_table :tenant_customers do |t|
      t.string :name, null: false
      t.string :email
      t.string :phone
      t.string :address
      t.text :notes
      t.references :business, null: false, foreign_key: true
      t.datetime :last_appointment
      t.boolean :active, default: true

      t.timestamps
    end

    add_index :tenant_customers, [:email, :business_id], unique: true
  end
end 