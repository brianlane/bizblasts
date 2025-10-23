# frozen_string_literal: true

class FixPhoneUniqueIndexForUsers < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    # Drop the incorrect triple-column unique index if present
    if index_exists?(:tenant_customers, [:business_id, :phone_ciphertext, :user_id], name: :index_tenant_customers_on_business_phone_and_user_unique)
      remove_index :tenant_customers, name: :index_tenant_customers_on_business_phone_and_user_unique
    end

    # Add the correct partial unique index on business_id + phone_ciphertext
    # Enforce uniqueness only for linked users (user_id IS NOT NULL)
    unless index_exists?(:tenant_customers, [:business_id, :phone_ciphertext], name: :idx_tenant_cust_on_biz_and_phone_users_only)
      add_index :tenant_customers, [:business_id, :phone_ciphertext],
                unique: true,
                where: "user_id IS NOT NULL",
                algorithm: :concurrently,
                name: :idx_tenant_cust_on_biz_and_phone_users_only
    end
  end

  def down
    # Remove the corrected index
    if index_exists?(:tenant_customers, [:business_id, :phone_ciphertext], name: :idx_tenant_cust_on_biz_and_phone_users_only)
      remove_index :tenant_customers, name: :idx_tenant_cust_on_biz_and_phone_users_only
    end

    # Re-create the previous (incorrect) index only if needed for rollback symmetry
    unless index_exists?(:tenant_customers, [:business_id, :phone_ciphertext, :user_id], name: :index_tenant_customers_on_business_phone_and_user_unique)
      add_index :tenant_customers, [:business_id, :phone_ciphertext, :user_id],
                unique: true,
                where: "user_id IS NOT NULL",
                algorithm: :concurrently,
                name: :index_tenant_customers_on_business_phone_and_user_unique
    end
  end
end
