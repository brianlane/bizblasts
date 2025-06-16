class AddEmailMarketingOptOutToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :email_marketing_opt_out, :boolean
  end
end
