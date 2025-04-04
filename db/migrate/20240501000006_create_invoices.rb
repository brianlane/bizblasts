class CreateInvoices < ActiveRecord::Migration[8.0]
  def change
    create_table :invoices do |t|
      t.string :invoice_number, null: false
      t.datetime :due_date
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.decimal :tax_amount, precision: 10, scale: 2, default: 0.0
      t.decimal :total_amount, precision: 10, scale: 2, null: false
      t.integer :status, default: 0
      t.references :booking, foreign_key: true
      t.references :tenant_customer, null: false, foreign_key: true
      t.references :business, null: false, foreign_key: true
      
      t.timestamps
    end
    
    add_index :invoices, :invoice_number
    add_index :invoices, :status
  end
end
