# frozen_string_literal: true

class DropPlatformLoyaltyTables < ActiveRecord::Migration[7.1]
  def change
    # Drop in dependency order due to foreign keys.
    drop_table :platform_loyalty_transactions, if_exists: true
    drop_table :platform_discount_codes, if_exists: true
    drop_table :platform_referrals, if_exists: true
  end
end

