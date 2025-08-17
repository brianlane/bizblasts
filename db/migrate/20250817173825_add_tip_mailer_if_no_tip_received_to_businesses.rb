class AddTipMailerIfNoTipReceivedToBusinesses < ActiveRecord::Migration[8.0]
  def change
    add_column :businesses, :tip_mailer_if_no_tip_received, :boolean, default: true, null: false
  end
end
