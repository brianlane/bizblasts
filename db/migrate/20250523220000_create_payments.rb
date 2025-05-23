class CreatePayments < ActiveRecord::Migration[8.0]
  def change
    create_table :payments do |t|
      # Core relationships
      t.references :business, null: false, foreign_key: { on_delete: :cascade }
      t.references :invoice, null: false, foreign_key: true
      t.references :order, null: true, foreign_key: true
      t.references :tenant_customer, null: false, foreign_key: true

      # Payment amounts
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.decimal :platform_fee_amount, precision: 10, scale: 2, null: false
      t.decimal :stripe_fee_amount, precision: 10, scale: 2, null: false
      t.decimal :business_amount, precision: 10, scale: 2, null: false

      # Essential Stripe IDs
      t.string :stripe_payment_intent_id, null: false
      t.string :stripe_charge_id
      t.string :stripe_customer_id
      t.string :stripe_transfer_id

      # Payment details
      t.string :payment_method, default: 'card'
      t.integer :status, default: 0
      t.datetime :paid_at
      t.text :failure_reason

      # Refund tracking
      t.decimal :refunded_amount, precision: 10, scale: 2, default: 0
      t.text :refund_reason

      t.timestamps
    end

    # Critical indexes
    add_index :payments, :stripe_payment_intent_id, unique: true
    add_index :payments, :stripe_charge_id
    add_index :payments, [:business_id, :status]
    add_index :payments, [:business_id, :paid_at]
  end
end 