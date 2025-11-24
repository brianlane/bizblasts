# frozen_string_literal: true

class EnforceUniquePhoneNumbers < ActiveRecord::Migration[8.0]
  disable_ddl_transaction! # allow concurrent index creation

  def up
    say_with_time "Checking for duplicate phone numbers" do
      dupes = TenantCustomer.where.not(phone_ciphertext: nil)
        .group(:phone_ciphertext, :business_id)
        .having("COUNT(*) > 1")
        .pluck(:phone_ciphertext, :business_id, Arel.sql('COUNT(*)'))

      if dupes.any?
        message_lines = dupes.map { |cipher, biz, count| "business_id=#{biz} duplicates=#{count}" }
        raise <<~MSG
          Duplicate phone numbers detected, aborting unique-index creation.\n\n#{message_lines.join("\n")}\n\nFix duplicates first, then rerun the migration.
        MSG
      end
    end

    # Only enforce uniqueness for linked users (where user_id IS NOT NULL)
    # Guests (user_id IS NULL) can share phone numbers with users
    unless index_exists?(:tenant_customers, [:business_id, :phone_ciphertext], name: :index_tenant_customers_on_business_phone_unique)
      add_index :tenant_customers, [:business_id, :phone_ciphertext],
                unique: true,
                where: "user_id IS NOT NULL",
                algorithm: :concurrently,
                name: :index_tenant_customers_on_business_phone_unique
    end
  end

  def down
    if index_exists?(:tenant_customers, [:business_id, :phone_ciphertext], name: :index_tenant_customers_on_business_phone_unique)
      remove_index :tenant_customers, name: :index_tenant_customers_on_business_phone_unique
    end
  end
end
