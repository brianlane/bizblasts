class CreateReferrals < ActiveRecord::Migration[8.0]
  def change
    create_table :referrals do |t|
      t.references :business, null: false, foreign_key: { on_delete: :cascade }
      t.references :referrer, null: false, foreign_key: { to_table: :users }
      t.references :referred_user, null: false, foreign_key: { to_table: :users }
      t.string :referral_code, null: false
      t.string :status, default: 'pending', null: false
      t.datetime :reward_issued_at
      t.datetime :referred_signup_at
      t.datetime :qualification_met_at
      t.references :qualifying_booking, foreign_key: { to_table: :bookings }, null: true
      t.references :qualifying_order, foreign_key: { to_table: :orders }, null: true

      t.timestamps
    end
    
    add_index :referrals, [:business_id, :referral_code], unique: true
    add_index :referrals, :status
    add_index :referrals, :referral_code
  end
end
