class MakeTenantCustomerOptionalInDiscountCodes < ActiveRecord::Migration[8.0]
  def change
    change_column_null :discount_codes, :tenant_customer_id, true
  end
end
