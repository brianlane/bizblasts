class ChangeLoyaltyProgramEnabledDefaultToFalse < ActiveRecord::Migration[8.0]
  def change
    change_column_default :businesses, :loyalty_program_enabled, from: true, to: false
  end
end
