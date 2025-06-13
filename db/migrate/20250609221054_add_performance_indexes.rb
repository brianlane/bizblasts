class AddPerformanceIndexes < ActiveRecord::Migration[8.0]
  def change
    # High-impact indexes for cross-business user lookups
    add_index :tenant_customers, [:email, :business_id], if_not_exists: true
    
    # Dashboard query optimizations
    add_index :bookings, [:tenant_customer_id, :start_time], if_not_exists: true
    add_index :orders, [:tenant_customer_id, :created_at], if_not_exists: true
    
    # Loyalty system optimizations
    add_index :loyalty_transactions, [:tenant_customer_id, :transaction_type], if_not_exists: true
    
    # Authentication and role-based queries
    add_index :users, [:email, :role], if_not_exists: true
    
    # Additional commonly queried combinations
    add_index :bookings, [:business_id, :start_time], if_not_exists: true
    add_index :orders, [:business_id, :created_at], if_not_exists: true
  end
end
