class AddAllowCustomerPreferencesToProductsAndServices < ActiveRecord::Migration[8.0]
  def change
    add_column :products, :allow_customer_preferences, :boolean, default: true, null: false
    add_column :services, :allow_customer_preferences, :boolean, default: true, null: false
    
    add_index :products, :allow_customer_preferences
    add_index :services, :allow_customer_preferences
  end
end
