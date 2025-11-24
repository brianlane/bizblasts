class AddSmsEnabledToBusinesses < ActiveRecord::Migration[8.0]
  def change
    add_column :businesses, :sms_enabled, :boolean, default: false, null: false
    add_column :businesses, :sms_marketing_enabled, :boolean, default: false, null: false
  end
end
