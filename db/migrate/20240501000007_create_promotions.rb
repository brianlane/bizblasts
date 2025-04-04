class CreatePromotions < ActiveRecord::Migration[8.0]
  def change
    create_table :promotions do |t|
      t.string :name, null: false
      t.string :code, null: false
      t.text :description
      t.integer :discount_type, default: 0
      t.decimal :discount_value, precision: 10, scale: 2, null: false
      t.datetime :start_date
      t.datetime :end_date
      t.integer :usage_limit
      t.integer :current_usage, default: 0
      t.boolean :active, default: true
      t.references :business, null: false, foreign_key: true
      
      t.timestamps
    end
    
    add_index :promotions, [:code, :business_id], unique: true
    
    create_table :promotion_redemptions do |t|
      t.references :promotion, null: false, foreign_key: true
      t.references :tenant_customer, null: false, foreign_key: true
      t.references :booking, foreign_key: true
      t.references :invoice, foreign_key: true
      t.datetime :redeemed_at
      
      t.timestamps
    end
  end
end
