class AddPromotionFieldsToInvoices < ActiveRecord::Migration[7.1]
  def change
    add_reference :invoices, :promotion, foreign_key: true
    add_column :invoices, :original_amount, :decimal, precision: 10, scale: 2
    add_column :invoices, :discount_amount, :decimal, precision: 10, scale: 2
  end
end
