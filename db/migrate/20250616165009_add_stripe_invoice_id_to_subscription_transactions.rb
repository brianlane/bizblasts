class AddStripeInvoiceIdToSubscriptionTransactions < ActiveRecord::Migration[8.0]
  def change
    add_column :subscription_transactions, :stripe_invoice_id, :string
  end
end
