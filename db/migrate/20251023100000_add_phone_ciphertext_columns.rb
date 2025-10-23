# frozen_string_literal: true

class AddPhoneCiphertextColumns < ActiveRecord::Migration[8.0]
  def change
    # TenantCustomer phone encryption support
    add_column :tenant_customers, :phone_ciphertext, :text
    # Deterministic encryption allows equality look-ups; index it for uniqueness
    add_index  :tenant_customers, :phone_ciphertext, unique: true, name: :index_tenant_customers_on_phone_ciphertext

    # SmsMessage phone_number encryption support
    add_column :sms_messages, :phone_number_ciphertext, :text
    add_index  :sms_messages, :phone_number_ciphertext, name: :index_sms_messages_on_phone_number_ciphertext
  end
end
