# frozen_string_literal: true

class FixPhoneUniqueIndexForUsers < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    # Drop the incorrect triple-column unique index if present
    # The correct index (index_tenant_customers_on_business_phone_unique) is already
    # created by migration 20251022223000_enforce_unique_phone_numbers.rb
    if index_exists?(:tenant_customers, [:business_id, :phone_ciphertext, :user_id], name: :index_tenant_customers_on_business_phone_and_user_unique)
      remove_index :tenant_customers, name: :index_tenant_customers_on_business_phone_and_user_unique
    end
  end

  def down
    # Re-create the previous (incorrect) index for rollback symmetry
    unless index_exists?(:tenant_customers, [:business_id, :phone_ciphertext, :user_id], name: :index_tenant_customers_on_business_phone_and_user_unique)
      add_index :tenant_customers, [:business_id, :phone_ciphertext, :user_id],
                unique: true,
                where: "user_id IS NOT NULL",
                algorithm: :concurrently,
                name: :index_tenant_customers_on_business_phone_and_user_unique
    end
  end
end
