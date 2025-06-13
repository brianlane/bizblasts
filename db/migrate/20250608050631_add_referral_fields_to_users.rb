class AddReferralFieldsToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :referral_source_code, :string
  end
end
