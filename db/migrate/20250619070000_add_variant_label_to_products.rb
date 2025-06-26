class AddVariantLabelToProducts < ActiveRecord::Migration[8.0]
  def change
    add_column :products, :variant_label_text, :string, default: 'Choose a variant'
    add_column :products, :hide_variant_label_single, :boolean, default: false, null: false
    
    add_index :products, :hide_variant_label_single
  end
end 