# frozen_string_literal: true

class RemoveRedundantPhoneCiphertextIndex < ActiveRecord::Migration[8.0]
  def change
    if index_exists?(:tenant_customers, :phone_ciphertext, name: :index_tenant_customers_on_phone_ciphertext, unique: false)
      remove_index :tenant_customers, name: :index_tenant_customers_on_phone_ciphertext
    end
  end
end
