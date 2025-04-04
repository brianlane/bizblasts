class CreateBusinesses < ActiveRecord::Migration[8.0]
  def change
    create_table :businesses do |t|
      t.string :name, null: false
      t.string :subdomain, null: false
      t.string :industry
      t.string :phone
      t.string :email
      t.string :website
      t.string :address
      t.string :city
      t.string :state
      t.string :zip
      t.text :description
      t.string :time_zone, default: "UTC"
      t.boolean :active, default: true
      
      t.timestamps
    end
    
    add_index :businesses, :subdomain, unique: true
    add_index :businesses, :name
  end
end
