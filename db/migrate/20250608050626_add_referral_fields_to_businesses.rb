class AddReferralFieldsToBusinesses < ActiveRecord::Migration[8.0]
  def change
    add_column :businesses, :referral_program_enabled, :boolean, default: false, null: false
    add_column :businesses, :loyalty_program_enabled, :boolean, default: true, null: false
    add_column :businesses, :points_per_dollar, :decimal, precision: 8, scale: 2, default: 1.0, null: false
    add_column :businesses, :points_per_service, :decimal, precision: 8, scale: 2, default: 0.0, null: false
    add_column :businesses, :points_per_product, :decimal, precision: 8, scale: 2, default: 0.0, null: false
  end
end
