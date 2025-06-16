class AddTrialEndDateToCustomerSubscriptions < ActiveRecord::Migration[8.0]
  def change
    add_column :customer_subscriptions, :trial_end_date, :date
  end
end
