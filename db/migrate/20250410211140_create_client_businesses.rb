class CreateClientBusinesses < ActiveRecord::Migration[8.0]
  def change
    create_table :client_businesses do |t|
      t.references :user, null: false, foreign_key: true
      t.references :business, null: false, foreign_key: true

      t.timestamps
    end
    
    # Add a unique index to ensure a user can only be linked to a business once
    add_index :client_businesses, [:user_id, :business_id], unique: true
  end
end
