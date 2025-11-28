class MakeProductTypeRequired < ActiveRecord::Migration[8.1]
  def up
    # Set default for existing records
    Product.where(product_type: nil).update_all(product_type: 0)
    change_column_null :products, :product_type, false
  end

  def down
    change_column_null :products, :product_type, true
  end
end
