class AddStripeAccountIdToBusinesses < ActiveRecord::Migration[8.0]
  def change
    add_column :businesses, :stripe_account_id, :string
    add_index :businesses, :stripe_account_id, unique: true
  end
end 