class CreatePlatformLoyaltyTransactions < ActiveRecord::Migration[8.0]
  def change
    create_table :platform_loyalty_transactions do |t|
      t.references :business, null: false, foreign_key: { on_delete: :cascade }
      t.string :transaction_type, null: false
      t.integer :points_amount, null: false
      t.text :description, null: false
      t.references :related_platform_referral, foreign_key: { to_table: :platform_referrals }, null: true

      t.timestamps
    end
    
    add_index :platform_loyalty_transactions, :transaction_type
    add_index :platform_loyalty_transactions, :created_at
  end
end
