class AddValidForDaysToEstimates < ActiveRecord::Migration[8.1]
  def change
    add_column :estimates, :valid_for_days, :integer, null: false, default: 30
  end
end
