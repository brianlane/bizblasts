# frozen_string_literal: true

# Bug Fix: Remove global unique index on phone_ciphertext
# This index incorrectly enforces global uniqueness across all businesses and for all users.
# The correct behavior is enforced by the partial unique index:
#   index_tenant_customers_on_business_phone_and_user_unique
# which only applies to linked users (user_id IS NOT NULL) within each business.
class RemoveGlobalPhoneCiphertextUniqueIndex < ActiveRecord::Migration[8.0]
  def up
    # Remove the incorrect global unique index if it exists
    if index_exists?(:tenant_customers, :phone_ciphertext, name: :index_tenant_customers_on_phone_ciphertext_unique)
      remove_index :tenant_customers, name: :index_tenant_customers_on_phone_ciphertext_unique
    end
  end

  def down
    # Don't recreate the incorrect index in rollback
    # If someone rolls back, they should manually fix the issue
    raise ActiveRecord::IrreversibleMigration, "Cannot recreate the incorrect global unique index"
  end
end
