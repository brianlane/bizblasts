class AddPhoneNumberBackToSmsMessages < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!
  
  def up
    # Add phone_number column to store encrypted data (Rails convention: same name as attribute)
    add_column :sms_messages, :phone_number, :text unless column_exists?(:sms_messages, :phone_number)
    
    # Copy existing encrypted data from phone_number_ciphertext to phone_number
    if column_exists?(:sms_messages, :phone_number_ciphertext)
      execute <<-SQL
        UPDATE sms_messages 
        SET phone_number = phone_number_ciphertext 
        WHERE phone_number_ciphertext IS NOT NULL
      SQL
    end
    
    # Add index for querying with deterministic encryption
    add_index :sms_messages, :phone_number, 
              algorithm: :concurrently,
              if_not_exists: true
  end
  
  def down
    remove_index :sms_messages, :phone_number, algorithm: :concurrently if index_exists?(:sms_messages, :phone_number)
    remove_column :sms_messages, :phone_number if column_exists?(:sms_messages, :phone_number)
  end
end
