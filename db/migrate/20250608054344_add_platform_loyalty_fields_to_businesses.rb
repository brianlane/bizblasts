class AddPlatformLoyaltyFieldsToBusinesses < ActiveRecord::Migration[8.0]
  def change
    add_column :businesses, :platform_loyalty_points, :integer, default: 0, null: false
    add_column :businesses, :platform_referral_code, :string
    
    add_index :businesses, :platform_referral_code, unique: true
  end
end
