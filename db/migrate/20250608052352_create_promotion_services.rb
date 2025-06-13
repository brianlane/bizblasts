class CreatePromotionServices < ActiveRecord::Migration[8.0]
  def change
    create_table :promotion_services do |t|
      t.references :promotion, null: false, foreign_key: { on_delete: :cascade }
      t.references :service, null: false, foreign_key: { on_delete: :cascade }

      t.timestamps
    end
    
    add_index :promotion_services, [:promotion_id, :service_id], unique: true
  end
end
