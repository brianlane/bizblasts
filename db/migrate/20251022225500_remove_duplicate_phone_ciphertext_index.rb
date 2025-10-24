# frozen_string_literal: true

class RemoveDuplicatePhoneCiphertextIndex < ActiveRecord::Migration[8.0]
  def change
    # Keep the _unique index, remove the original one
    if index_exists?(:tenant_customers, :phone_ciphertext, name: :index_tenant_customers_on_phone_ciphertext)
      remove_index :tenant_customers, name: :index_tenant_customers_on_phone_ciphertext
    end
  end
end

