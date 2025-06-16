class CreateCustomerSubscriptions < ActiveRecord::Migration[8.0]
  def up
    # NOTE: This table already exists in the database
    # This migration is here for version control consistency
    # The actual table creation is handled by MarkSubscriptionTablesAsApplied
    
    return if table_exists?(:customer_subscriptions)
    
    create_table :customer_subscriptions do |t|
      t.references :business, null: false, foreign_key: { on_delete: :cascade }
      t.references :tenant_customer, null: false, foreign_key: true
      t.references :product, null: true, foreign_key: true
      t.references :service, null: true, foreign_key: true
      t.references :product_variant, null: true, foreign_key: true
      t.string :subscription_type, null: false
      t.integer :status, default: 0, null: false
      t.integer :quantity, default: 1, null: false
      t.date :next_billing_date, null: false
      t.integer :billing_day_of_month, null: false
      t.date :last_processed_date
      t.integer :service_rebooking_preference
      t.time :preferred_time_slot
      t.references :preferred_staff_member, null: true, foreign_key: { to_table: :staff_members }
      t.integer :out_of_stock_action, default: 0
      t.decimal :subscription_price, precision: 10, scale: 2, null: false
      t.text :notes
      t.datetime :cancelled_at
      t.text :cancellation_reason
      t.string :stripe_subscription_id

      t.timestamps
    end

    # Indexes
    add_index :customer_subscriptions, [:business_id, :status]
    add_index :customer_subscriptions, [:next_billing_date, :status]
    add_index :customer_subscriptions, [:subscription_type, :status]
    add_index :customer_subscriptions, [:tenant_customer_id, :status]
    add_index :customer_subscriptions, :stripe_subscription_id, unique: true

    # Check constraint to ensure either product_id OR service_id is present
    add_check_constraint :customer_subscriptions, 
      "product_id IS NOT NULL AND service_id IS NULL OR product_id IS NULL AND service_id IS NOT NULL",
      name: "customer_subscriptions_product_or_service_check"
  end
  
  def down
    drop_table :customer_subscriptions if table_exists?(:customer_subscriptions)
  end
end
