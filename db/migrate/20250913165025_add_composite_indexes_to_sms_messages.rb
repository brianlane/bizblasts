class AddCompositeIndexesToSmsMessages < ActiveRecord::Migration[8.0]
  def change
    # Composite index for business_id + created_at (used by rate limiter for business counts)
    add_index :sms_messages, [:business_id, :created_at], name: 'index_sms_messages_on_business_id_and_created_at'
    
    # Composite index for tenant_customer_id + created_at (used by rate limiter for customer counts)
    add_index :sms_messages, [:tenant_customer_id, :created_at], name: 'index_sms_messages_on_tenant_customer_id_and_created_at'
  end
end
