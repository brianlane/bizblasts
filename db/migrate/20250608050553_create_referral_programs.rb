class CreateReferralPrograms < ActiveRecord::Migration[8.0]
  def change
    create_table :referral_programs do |t|
      t.references :business, null: false, foreign_key: { on_delete: :cascade }
      t.boolean :active, default: true, null: false
      t.string :referrer_reward_type, default: 'points', null: false
      t.decimal :referrer_reward_value, precision: 10, scale: 2, default: 0.0, null: false
      t.string :referred_reward_type, default: 'discount', null: false
      t.decimal :referred_reward_value, precision: 10, scale: 2, default: 0.0, null: false
      t.decimal :min_purchase_amount, precision: 10, scale: 2, default: 0.0

      t.timestamps
    end
    
    add_index :referral_programs, :active
  end
end
