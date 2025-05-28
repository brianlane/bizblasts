class FixForeignKeyConstraintsForBusinessDeletion < ActiveRecord::Migration[8.0]
  def up
    # Remove existing foreign key constraints and add them back with cascade delete
    # This will allow proper deletion of businesses and their related records
    
    # Fix invoices -> tenant_customers relationship
    remove_foreign_key :invoices, :tenant_customers
    add_foreign_key :invoices, :tenant_customers, on_delete: :cascade
    
    # Fix other problematic relationships that don't have cascade delete
    # These were identified from the schema as having foreign keys without cascade
    
    # booking_policies -> businesses
    remove_foreign_key :booking_policies, :businesses
    add_foreign_key :booking_policies, :businesses, on_delete: :cascade
    
    # categories -> businesses  
    remove_foreign_key :categories, :businesses
    add_foreign_key :categories, :businesses, on_delete: :cascade
    
    # integration_credentials -> businesses
    remove_foreign_key :integration_credentials, :businesses
    add_foreign_key :integration_credentials, :businesses, on_delete: :cascade
    
    # integrations -> businesses
    remove_foreign_key :integrations, :businesses
    add_foreign_key :integrations, :businesses, on_delete: :cascade
    
    # locations -> businesses
    remove_foreign_key :locations, :businesses
    add_foreign_key :locations, :businesses, on_delete: :cascade
    
    # notification_templates -> businesses
    remove_foreign_key :notification_templates, :businesses
    add_foreign_key :notification_templates, :businesses, on_delete: :cascade
    
    # orders -> businesses (but keep orders -> tenant_customers without cascade to preserve order history)
    remove_foreign_key :orders, :businesses
    add_foreign_key :orders, :businesses, on_delete: :cascade
    
    # products -> businesses
    remove_foreign_key :products, :businesses
    add_foreign_key :products, :businesses, on_delete: :cascade
    
    # shipping_methods -> businesses
    remove_foreign_key :shipping_methods, :businesses
    add_foreign_key :shipping_methods, :businesses, on_delete: :cascade
    
    # subscriptions -> businesses
    remove_foreign_key :subscriptions, :businesses
    add_foreign_key :subscriptions, :businesses, on_delete: :cascade
    
    # tax_rates -> businesses
    remove_foreign_key :tax_rates, :businesses
    add_foreign_key :tax_rates, :businesses, on_delete: :cascade
  end

  def down
    # Reverse the changes - remove cascade delete from all relationships
    
    remove_foreign_key :invoices, :tenant_customers
    add_foreign_key :invoices, :tenant_customers
    
    remove_foreign_key :booking_policies, :businesses
    add_foreign_key :booking_policies, :businesses
    
    remove_foreign_key :categories, :businesses
    add_foreign_key :categories, :businesses
    
    remove_foreign_key :integration_credentials, :businesses
    add_foreign_key :integration_credentials, :businesses
    
    remove_foreign_key :integrations, :businesses
    add_foreign_key :integrations, :businesses
    
    remove_foreign_key :locations, :businesses
    add_foreign_key :locations, :businesses
    
    remove_foreign_key :notification_templates, :businesses
    add_foreign_key :notification_templates, :businesses
    
    remove_foreign_key :orders, :businesses
    add_foreign_key :orders, :businesses
    
    remove_foreign_key :products, :businesses
    add_foreign_key :products, :businesses
    
    remove_foreign_key :shipping_methods, :businesses
    add_foreign_key :shipping_methods, :businesses
    
    remove_foreign_key :subscriptions, :businesses
    add_foreign_key :subscriptions, :businesses
    
    remove_foreign_key :tax_rates, :businesses
    add_foreign_key :tax_rates, :businesses
  end
end
