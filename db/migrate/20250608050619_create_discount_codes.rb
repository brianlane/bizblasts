class CreateDiscountCodes < ActiveRecord::Migration[8.0]
  def change
    create_table :discount_codes do |t|
      t.references :business, null: false, foreign_key: { on_delete: :cascade }
      t.string :code, null: false
      t.string :discount_type, null: false
      t.decimal :discount_value, precision: 10, scale: 2, null: false
      t.boolean :single_use, default: true, null: false
      t.bigint :used_by_customer_id
      t.datetime :expires_at
      t.boolean :active, default: true, null: false
      t.integer :usage_count, default: 0, null: false
      t.integer :max_usage, default: 1
      t.references :generated_by_referral, foreign_key: { to_table: :referrals }, null: true

      t.timestamps
    end
    
    add_index :discount_codes, :code
    add_index :discount_codes, :active
    add_index :discount_codes, :expires_at
    add_index :discount_codes, :used_by_customer_id
    add_foreign_key :discount_codes, :tenant_customers, column: :used_by_customer_id, on_delete: :nullify
  end
end
