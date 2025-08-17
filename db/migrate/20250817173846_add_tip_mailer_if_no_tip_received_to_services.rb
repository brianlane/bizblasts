class AddTipMailerIfNoTipReceivedToServices < ActiveRecord::Migration[8.0]
  def change
    add_column :services, :tip_mailer_if_no_tip_received, :boolean, default: true, null: false
  end
end
