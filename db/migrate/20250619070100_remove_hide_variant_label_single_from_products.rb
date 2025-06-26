class RemoveHideVariantLabelSingleFromProducts < ActiveRecord::Migration[8.0]
  def change
    remove_index :products, :hide_variant_label_single
    remove_column :products, :hide_variant_label_single, :boolean
  end
end 