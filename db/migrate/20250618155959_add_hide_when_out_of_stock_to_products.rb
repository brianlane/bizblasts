class AddHideWhenOutOfStockToProducts < ActiveRecord::Migration[8.0]
  def change
    add_column :products, :hide_when_out_of_stock, :boolean, default: false, null: false
  end
end
