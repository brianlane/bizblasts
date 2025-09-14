class AddBusinessIdToSmsMessages < ActiveRecord::Migration[8.0]
  def up
    # Add column as nullable first
    add_column :sms_messages, :business_id, :bigint
    
    # Populate business_id for existing records
    execute <<-SQL
      UPDATE sms_messages 
      SET business_id = tenant_customers.business_id 
      FROM tenant_customers 
      WHERE sms_messages.tenant_customer_id = tenant_customers.id
    SQL
    
    # Make it non-nullable and add constraints
    change_column_null :sms_messages, :business_id, false
    add_index :sms_messages, :business_id
    add_foreign_key :sms_messages, :businesses
  end

  def down
    remove_foreign_key :sms_messages, :businesses
    remove_index :sms_messages, :business_id
    remove_column :sms_messages, :business_id
  end
end
