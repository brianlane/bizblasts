class RemoveLegacyPhoneNumberCiphertextFromSmsMessages < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!
  
  def up
    # Remove the legacy index first (if it exists)
    if index_exists?(:sms_messages, :phone_number_ciphertext)
      remove_index :sms_messages, :phone_number_ciphertext, algorithm: :concurrently
    end
    
    # Remove the legacy column (phone_number is now used for encrypted data)
    if column_exists?(:sms_messages, :phone_number_ciphertext)
      remove_column :sms_messages, :phone_number_ciphertext
    end
  end
  
  def down
    # Re-add the column for rollback (though data would be lost)
    add_column :sms_messages, :phone_number_ciphertext, :text unless column_exists?(:sms_messages, :phone_number_ciphertext)
    
    # Re-add the index
    unless index_exists?(:sms_messages, :phone_number_ciphertext)
      add_index :sms_messages, :phone_number_ciphertext, algorithm: :concurrently
    end
  end
end
