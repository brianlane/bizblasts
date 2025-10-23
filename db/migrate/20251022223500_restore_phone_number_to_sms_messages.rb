# frozen_string_literal: true

class RestorePhoneNumberToSmsMessages < ActiveRecord::Migration[8.0]
  def change
    unless column_exists?(:sms_messages, :phone_number)
      add_column :sms_messages, :phone_number, :string
      # Optional: populate from ciphertext for legacy code paths (unencrypted read)
      reversible do |dir|
        dir.up do
          SmsMessage.reset_column_information
          SmsMessage.find_each do |msg|
            next unless msg.respond_to?(:phone_number_ciphertext)
            plain = msg.phone_number rescue nil
            # phone_number virtual attr decrypts ciphertext
            SmsMessage.where(id: msg.id).update_all(phone_number: plain)
          end
        end
      end
    end
  end
end
