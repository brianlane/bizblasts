class AddFailureReasonToCustomerSubscriptions < ActiveRecord::Migration[8.0]
  def change
    add_column :customer_subscriptions, :failure_reason, :text
  end
end
