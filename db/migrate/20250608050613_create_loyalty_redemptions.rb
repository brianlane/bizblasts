class CreateLoyaltyRedemptions < ActiveRecord::Migration[8.0]
  def change
    create_table :loyalty_redemptions do |t|
      t.references :business, null: false, foreign_key: { on_delete: :cascade }
      t.references :tenant_customer, null: false, foreign_key: { on_delete: :cascade }
      t.references :loyalty_reward, null: false, foreign_key: { on_delete: :cascade }
      t.references :booking, foreign_key: { on_delete: :nullify }, null: true
      t.references :order, foreign_key: { on_delete: :nullify }, null: true
      t.integer :points_redeemed, null: false
      t.string :status, default: 'active', null: false
      t.decimal :discount_amount_applied, precision: 10, scale: 2
      t.string :discount_code, null: false

      t.timestamps
    end
    
    add_index :loyalty_redemptions, :discount_code, unique: true
    add_index :loyalty_redemptions, :status
    add_index :loyalty_redemptions, :created_at
  end
end
