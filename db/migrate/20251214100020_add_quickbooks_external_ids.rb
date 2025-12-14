# frozen_string_literal: true

class AddQuickbooksExternalIds < ActiveRecord::Migration[8.1]
  def change
    add_column :tenant_customers, :quickbooks_customer_id, :string

    add_column :services, :quickbooks_item_id, :string
    add_column :product_variants, :quickbooks_item_id, :string

    add_column :invoices, :quickbooks_invoice_id, :string
    add_column :invoices, :quickbooks_exported_at, :datetime
    add_column :invoices, :quickbooks_export_status, :integer, null: false, default: 0

    add_column :payments, :quickbooks_payment_id, :string

    add_index :tenant_customers, :quickbooks_customer_id
    add_index :services, :quickbooks_item_id
    add_index :product_variants, :quickbooks_item_id
    add_index :invoices, :quickbooks_invoice_id
    add_index :payments, :quickbooks_payment_id
  end
end
