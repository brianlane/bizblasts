class CreateBookings < ActiveRecord::Migration[8.0]
  def change
    create_table :bookings do |t|
      t.datetime :start_time, null: false
      t.datetime :end_time, null: false
      t.integer :status, default: 0
      t.text :notes
      t.references :service, null: false, foreign_key: true
      t.references :staff_member, null: false, foreign_key: true
      t.references :tenant_customer, null: false, foreign_key: true
      t.references :business, null: false, foreign_key: true
      
      t.timestamps
    end
    
    add_index :bookings, :start_time
    add_index :bookings, :status
  end
end 