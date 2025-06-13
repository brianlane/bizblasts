class RefactorReferralsForGuestCheckout < ActiveRecord::Migration[8.0]
  def change
    # Remove the foreign key constraint first
    remove_foreign_key :referrals, :users, column: :referred_user_id, if_exists: true

    # Remove the old columns that tied referrals to user signups
    remove_column :referrals, :referred_user_id, :bigint, if_exists: true
    remove_column :referrals, :referred_signup_at, :datetime, if_exists: true

    # Add a new column to link the referral to the tenant_customer record
    # This is nullable because the record is created before a customer uses it.
    add_reference :referrals, :referred_tenant_customer, 
                  foreign_key: { to_table: :tenant_customers }, 
                  null: true, 
                  index: { name: 'index_referrals_on_referred_tenant_customer_id' }
  end
end
