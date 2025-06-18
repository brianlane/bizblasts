class UpdateTenantCustomerToUseFirstLastName < ActiveRecord::Migration[8.0]
  def change
    # Add columns as nullable first
    add_column :tenant_customers, :first_name, :string
    add_column :tenant_customers, :last_name, :string
    
    # Populate from existing name field
    reversible do |dir|
      dir.up do
        TenantCustomer.find_each do |customer|
          if customer.name.present?
            name_parts = customer.name.split(' ', 2)
            first_name = name_parts[0] || 'Unknown'
            last_name = name_parts[1] || 'Customer'
            customer.update_columns(first_name: first_name, last_name: last_name)
          else
            customer.update_columns(first_name: 'Unknown', last_name: 'Customer')
          end
        end
      end
    end
    
    # Make columns non-null
    change_column_null :tenant_customers, :first_name, false
    change_column_null :tenant_customers, :last_name, false
    
    # Remove the old name column
    remove_column :tenant_customers, :name, :string
  end
end
