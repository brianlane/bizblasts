# frozen_string_literal: true

class EncryptExistingPhoneNumbers < ActiveRecord::Migration[8.0]
  # This migration encrypts existing phone numbers in tenant_customers and sms_messages tables
  # Using deterministic encryption to maintain query capabilities

  def up
    # Encrypt existing phone numbers in tenant_customers
    say_with_time "Encrypting phone numbers in tenant_customers" do
      TenantCustomer.where.not(phone: nil).find_each do |customer|
        # Read the raw plaintext value (skip decryption) and then write it back so
        # Active Record encrypts it on save
        plaintext = ActiveRecord::Encryption.without_encryption { customer.read_attribute(:phone) }
        customer.update_column(:phone, plaintext)
      end
    end

    # Encrypt existing phone numbers in sms_messages
    say_with_time "Encrypting phone numbers in sms_messages" do
      SmsMessage.where.not(phone_number: nil).find_each do |message|
        # Read the raw plaintext value (skip decryption) and then write it back so
        # Active Record encrypts it on save
        plaintext = ActiveRecord::Encryption.without_encryption { message.read_attribute(:phone_number) }
        message.update_column(:phone_number, plaintext)
      end
    end
  end

  def down
    # Decryption happens automatically when models are loaded
    # No action needed for rollback since the data is stored encrypted
    say "Phone numbers will be automatically decrypted when accessed"
  end
end
