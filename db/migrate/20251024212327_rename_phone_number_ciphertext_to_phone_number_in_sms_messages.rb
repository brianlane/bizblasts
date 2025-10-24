class RenamePhoneNumberCiphertextToPhoneNumberInSmsMessages < ActiveRecord::Migration[8.0]
  def change
    # Rename the column to match Rails' encryption convention
    # This eliminates the need for alias_attribute
    rename_column :sms_messages, :phone_number_ciphertext, :phone_number
  end
end
