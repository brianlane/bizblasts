class RemoveTrialEndDateFromCustomerSubscriptions < ActiveRecord::Migration[8.0]
  def change
    remove_column :customer_subscriptions, :trial_end_date, :date
  end
end
