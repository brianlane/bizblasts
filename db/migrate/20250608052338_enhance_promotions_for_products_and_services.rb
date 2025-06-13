class EnhancePromotionsForProductsAndServices < ActiveRecord::Migration[8.0]
  def change
    add_column :promotions, :applicable_to_products, :boolean, default: true, null: false
    add_column :promotions, :applicable_to_services, :boolean, default: true, null: false
    add_column :promotions, :public_dates, :boolean, default: false, null: false
    add_column :promotions, :allow_discount_codes, :boolean, default: true, null: false
    
    add_index :promotions, :applicable_to_products
    add_index :promotions, :applicable_to_services
    add_index :promotions, :public_dates
  end
end
