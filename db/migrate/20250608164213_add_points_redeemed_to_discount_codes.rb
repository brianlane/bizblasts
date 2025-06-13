class AddPointsRedeemedToDiscountCodes < ActiveRecord::Migration[8.0]
  def change
    add_column :discount_codes, :points_redeemed, :integer, default: 0, null: false
    add_column :discount_codes, :stripe_coupon_id, :string
    
    add_index :discount_codes, :points_redeemed
    add_index :discount_codes, :stripe_coupon_id
  end
end
