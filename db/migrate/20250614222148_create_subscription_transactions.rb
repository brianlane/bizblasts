class CreateSubscriptionTransactions < ActiveRecord::Migration[8.0]
  def up
    # NOTE: This table already exists in the database
    # This migration is here for version control consistency
    # The actual table creation is handled by MarkSubscriptionTablesAsApplied
    
    return if table_exists?(:subscription_transactions)
    
    create_table :subscription_transactions do |t|
      t.references :customer_subscription, null: false, foreign_key: true
      t.references :business, null: false, foreign_key: { on_delete: :cascade }
      t.references :tenant_customer, null: false, foreign_key: true
      t.references :order, null: true, foreign_key: true
      t.references :booking, null: true, foreign_key: true
      t.references :invoice, null: true, foreign_key: true
      t.references :payment, null: true, foreign_key: true
      t.string :transaction_type, null: false
      t.integer :status, default: 0, null: false
      t.date :processed_date, null: false
      t.decimal :amount, precision: 10, scale: 2
      t.text :failure_reason
      t.integer :retry_count, default: 0
      t.datetime :next_retry_at
      t.integer :loyalty_points_awarded, default: 0
      t.jsonb :metadata
      t.text :notes

      t.timestamps
    end

    # Indexes
    add_index :subscription_transactions, [:business_id, :status]
    add_index :subscription_transactions, [:customer_subscription_id, :processed_date]
    add_index :subscription_transactions, [:transaction_type, :status]
    add_index :subscription_transactions, :next_retry_at
    add_index :subscription_transactions, :processed_date
  end
  
  def down
    drop_table :subscription_transactions if table_exists?(:subscription_transactions)
  end
end
