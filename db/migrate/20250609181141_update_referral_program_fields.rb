class UpdateReferralProgramFields < ActiveRecord::Migration[8.0]
  def change
    # Remove the referred_reward_type since referral codes always provide discount
    remove_column :referral_programs, :referred_reward_type, :string
    
    # Rename referred_reward_value to referral_code_discount_amount for clarity
    rename_column :referral_programs, :referred_reward_value, :referral_code_discount_amount
    
    # Force referrer_reward_type to always be 'points' in existing records
    change_column_default :referral_programs, :referrer_reward_type, 'points'
    
    # Update existing records
    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE referral_programs SET referrer_reward_type = 'points'
        SQL
      end
    end
  end
end
