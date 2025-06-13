class AddTipAmountToOrdersInvoicesPayments < ActiveRecord::Migration[8.0]
  def change
    add_column :orders, :tip_amount, :decimal, precision: 10, scale: 2, default: 0.0, null: false
    add_column :invoices, :tip_amount, :decimal, precision: 10, scale: 2, default: 0.0, null: false
    add_column :payments, :tip_amount, :decimal, precision: 10, scale: 2, default: 0.0, null: false
    
    add_index :orders, :tip_amount
    add_index :invoices, :tip_amount
    add_index :payments, :tip_amount
  end
end 