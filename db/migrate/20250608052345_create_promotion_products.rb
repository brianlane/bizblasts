class CreatePromotionProducts < ActiveRecord::Migration[8.0]
  def change
    create_table :promotion_products do |t|
      t.references :promotion, null: false, foreign_key: { on_delete: :cascade }
      t.references :product, null: false, foreign_key: { on_delete: :cascade }

      t.timestamps
    end
    
    add_index :promotion_products, [:promotion_id, :product_id], unique: true
  end
end
