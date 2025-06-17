class AddAllowDiscountsToProductsAndServices < ActiveRecord::Migration[8.0]
  def change
    add_column :products, :allow_discounts, :boolean, default: true, null: false
    add_column :services, :allow_discounts, :boolean, default: true, null: false
    
    # Ensure existing records have allow_discounts set to true
    reversible do |dir|
      dir.up do
        execute "UPDATE products SET allow_discounts = true WHERE allow_discounts IS NULL"
        execute "UPDATE services SET allow_discounts = true WHERE allow_discounts IS NULL"
      end
    end
    
    add_index :products, :allow_discounts
    add_index :services, :allow_discounts
  end
end 