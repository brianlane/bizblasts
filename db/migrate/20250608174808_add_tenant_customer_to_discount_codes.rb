class AddTenantCustomerToDiscountCodes < ActiveRecord::Migration[8.0]
  def change
    add_reference :discount_codes, :tenant_customer, null: false, foreign_key: true
  end
end
