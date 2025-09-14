class AddSmsOptInToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :phone_opt_in, :boolean, default: false, null: false
    add_column :users, :phone_opt_in_at, :datetime
    add_column :users, :phone_marketing_opt_out, :boolean, default: false, null: false
  end
end
