class AddPlatformFeePercentageToBusinesses < ActiveRecord::Migration[8.1]
  def change
    add_column :businesses,
               :platform_fee_percentage,
               :decimal,
               precision: 5,
               scale: 2,
               default: 1.0,
               null: false

    add_check_constraint :businesses,
                         "platform_fee_percentage >= 0",
                         name: "businesses_platform_fee_percentage_non_negative"
  end
end
