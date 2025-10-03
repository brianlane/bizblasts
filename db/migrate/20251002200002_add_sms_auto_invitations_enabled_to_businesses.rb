class AddSmsAutoInvitationsEnabledToBusinesses < ActiveRecord::Migration[8.0]
  def change
    add_column :businesses, :sms_auto_invitations_enabled, :boolean, default: true, null: false

    # Add index for efficient queries
    add_index :businesses, :sms_auto_invitations_enabled
  end
end