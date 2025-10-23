# frozen_string_literal: true

class AddPhoneCiphertextColumns < ActiveRecord::Migration[8.0]
  def change
    unless column_exists?(:tenant_customers, :phone_ciphertext)
      add_column :tenant_customers, :phone_ciphertext, :text
    end
    if index_exists?(:tenant_customers, :phone_ciphertext, name: :index_tenant_customers_on_phone_ciphertext, unique: true)
      remove_index :tenant_customers, name: :index_tenant_customers_on_phone_ciphertext
    end
    unless index_exists?(:tenant_customers, :phone_ciphertext, name: :index_tenant_customers_on_phone_ciphertext)
      add_index :tenant_customers, :phone_ciphertext, name: :index_tenant_customers_on_phone_ciphertext
    end

    unless column_exists?(:sms_messages, :phone_number_ciphertext)
      add_column :sms_messages, :phone_number_ciphertext, :text
    end
    unless index_exists?(:sms_messages, :phone_number_ciphertext, name: :index_sms_messages_on_phone_number_ciphertext)
      add_index :sms_messages, :phone_number_ciphertext, name: :index_sms_messages_on_phone_number_ciphertext
    end
  end
end
