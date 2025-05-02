class AddShippingMethodAndTaxRateToInvoices < ActiveRecord::Migration[8.0]
  def change
    add_reference :invoices, :shipping_method, foreign_key: true
    add_reference :invoices, :tax_rate, foreign_key: true
  end
end 