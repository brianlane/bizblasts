class CreateTips < ActiveRecord::Migration[8.0]
  def change
    create_table :tips do |t|
      t.references :business, null: false, foreign_key: true
      t.references :booking, null: false, foreign_key: true
      t.references :tenant_customer, null: false, foreign_key: true
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.decimal :stripe_fee_amount, precision: 10, scale: 2, default: 0.0, null: false
      t.decimal :platform_fee_amount, precision: 10, scale: 2, default: 0.0, null: false
      t.decimal :business_amount, precision: 10, scale: 2, null: false
      t.string :stripe_payment_intent_id
      t.string :stripe_charge_id
      t.string :stripe_customer_id
      t.integer :status, default: 0, null: false
      t.datetime :paid_at
      t.text :failure_reason

      t.timestamps
    end

    # Add indexes separately to handle any conflicts
    add_index :tips, [:business_id, :status] unless index_exists?(:tips, [:business_id, :status])
    add_index :tips, [:booking_id], unique: true unless index_exists?(:tips, [:booking_id])
    add_index :tips, [:stripe_payment_intent_id], unique: true, where: "(stripe_payment_intent_id IS NOT NULL)" unless index_exists?(:tips, [:stripe_payment_intent_id])
    add_index :tips, [:paid_at] unless index_exists?(:tips, [:paid_at])

    add_check_constraint :tips, "amount > 0", name: "tips_amount_positive"
  end
end
