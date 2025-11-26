class ChangeEstimatesTenantCustomerIdToOptional < ActiveRecord::Migration[8.0]
  def change
    change_column_null :estimates, :tenant_customer_id, true
  end
end
