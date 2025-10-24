# frozen_string_literal: true

class EncryptExistingPhoneNumbers < ActiveRecord::Migration[8.0]
  # This migration encrypts existing phone numbers in tenant_customers and sms_messages tables
  # Using deterministic encryption to maintain query capabilities

  def up
    # Encrypt existing phone numbers in tenant_customers
    TenantCustomer.reset_column_information if TenantCustomer.respond_to?(:reset_column_information)
    if TenantCustomer.column_names.include?("phone")
      say_with_time "Encrypting phone numbers in tenant_customers" do
        TenantCustomer.where.not(phone: nil).find_each do |customer|
          # Read the raw plaintext value (skip decryption) and then write it back so
          # Active Record encrypts it on save
          plaintext = ActiveRecord::Encryption.without_encryption { customer.read_attribute(:phone) }

          # Skip rows where ciphertext columns are not available yet or already populated
          unless customer.has_attribute?(:phone_ciphertext)
            Rails.logger&.debug("Skipping tenant_customer ##{customer.id} during phone encryption – ciphertext column missing")
            next
          end

          next if customer.read_attribute(:phone_ciphertext).present? || plaintext.blank?

          customer.update!(phone: plaintext)
        end
      end
    end

    # Encrypt existing phone numbers in sms_messages
    SmsMessage.reset_column_information if SmsMessage.respond_to?(:reset_column_information)
    if SmsMessage.column_names.include?("phone_number")
      say_with_time "Encrypting phone numbers in sms_messages" do
        SmsMessage.where.not(phone_number: nil).find_each do |message|
          # Read the raw plaintext value (skip decryption) and then write it back so
          # Active Record encrypts it on save
          plaintext = ActiveRecord::Encryption.without_encryption { message.read_attribute(:phone_number) }

          unless message.has_attribute?(:phone_number_ciphertext)
            Rails.logger&.debug("Skipping sms_message ##{message.id} during phone encryption – ciphertext column missing")
            next
          end

          next if message.read_attribute(:phone_number_ciphertext).present? || plaintext.blank?

          message.update!(phone_number: plaintext)
        end
      end
    end
  end

  def down
    # Decryption happens automatically when models are loaded
    # No action needed for rollback since the data is stored encrypted
    say "Phone numbers will be automatically decrypted when accessed"
  end
end
