class AddGuestAccessTokenToInvoices < ActiveRecord::Migration[8.0]
  def change
    add_column :invoices, :guest_access_token, :string
  end
end
