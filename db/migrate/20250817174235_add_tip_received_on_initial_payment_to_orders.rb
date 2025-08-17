class AddTipReceivedOnInitialPaymentToOrders < ActiveRecord::Migration[8.0]
  def change
    add_column :orders, :tip_received_on_initial_payment, :boolean, default: false, null: false
    add_column :orders, :tip_amount_received_initially, :decimal, precision: 10, scale: 2, default: 0.0
  end
end
