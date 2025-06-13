class ChangeTipsEnabledDefaultForBusinesses < ActiveRecord::Migration[8.0]
  def change
    change_column_default :businesses, :tips_enabled, from: false, to: true
  end
end
