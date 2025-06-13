class CreateLoyaltyTransactions < ActiveRecord::Migration[8.0]
  def change
    create_table :loyalty_transactions do |t|
      t.references :business, null: false, foreign_key: { on_delete: :cascade }
      t.references :tenant_customer, null: false, foreign_key: { on_delete: :cascade }
      t.string :transaction_type, null: false
      t.integer :points_amount, null: false
      t.text :description
      t.datetime :expires_at
      t.references :related_booking, foreign_key: { to_table: :bookings }, null: true
      t.references :related_order, foreign_key: { to_table: :orders }, null: true
      t.references :related_referral, foreign_key: { to_table: :referrals }, null: true

      t.timestamps
    end
    
    add_index :loyalty_transactions, :transaction_type
    add_index :loyalty_transactions, :created_at
    add_index :loyalty_transactions, :expires_at
  end
end
