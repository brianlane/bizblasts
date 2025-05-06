class AddReservedQuantityToProductVariants < ActiveRecord::Migration[8.0]
  def change
    add_column :product_variants, :reserved_quantity, :integer
  end
end
