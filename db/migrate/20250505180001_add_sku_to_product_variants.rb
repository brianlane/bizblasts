class AddSkuToProductVariants < ActiveRecord::Migration[8.0]
  def change
    add_column :product_variants, :sku, :string
  end
end
