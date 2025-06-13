class CreatePlatformReferrals < ActiveRecord::Migration[8.0]
  def change
    create_table :platform_referrals do |t|
      t.references :referrer_business, null: false, foreign_key: { to_table: :businesses, on_delete: :cascade }
      t.references :referred_business, null: false, foreign_key: { to_table: :businesses, on_delete: :cascade }
      t.string :referral_code, null: false
      t.string :status, default: 'pending', null: false
      t.datetime :qualification_met_at
      t.datetime :reward_issued_at

      t.timestamps
    end
    
    add_index :platform_referrals, :referral_code, unique: true
    add_index :platform_referrals, :status
  end
end
