class AddOptionsToProductVariants < ActiveRecord::Migration[8.0]
  def change
    add_column :product_variants, :options, :jsonb
  end
end
