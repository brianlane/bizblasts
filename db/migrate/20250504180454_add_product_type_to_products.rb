class AddProductTypeToProducts < ActiveRecord::Migration[8.0]
  def change
    add_column :products, :product_type, :integer
  end
end
