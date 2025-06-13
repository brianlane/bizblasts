class CreatePlatformDiscountCodes < ActiveRecord::Migration[8.0]
  def change
    create_table :platform_discount_codes do |t|
      t.references :business, null: false, foreign_key: { on_delete: :cascade }
      t.string :code, null: false
      t.integer :points_redeemed, null: false
      t.decimal :discount_amount, precision: 10, scale: 2, null: false
      t.string :status, default: 'active', null: false
      t.datetime :expires_at
      t.string :stripe_coupon_id

      t.timestamps
    end
    
    add_index :platform_discount_codes, :code, unique: true
    add_index :platform_discount_codes, :status
    add_index :platform_discount_codes, :stripe_coupon_id
    add_index :platform_discount_codes, :expires_at
  end
end
