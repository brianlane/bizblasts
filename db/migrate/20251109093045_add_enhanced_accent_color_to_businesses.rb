class AddEnhancedAccentColorToBusinesses < ActiveRecord::Migration[7.1]
  def change
    add_column :businesses, :enhanced_accent_color, :string, null: false, default: 'red'
  end
end

