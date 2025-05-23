class AddOrderToInvoices < ActiveRecord::Migration[8.0]
  def change
    # Link invoices to orders when applicable
    add_reference :invoices, :order, null: true, foreign_key: true
  end
end 