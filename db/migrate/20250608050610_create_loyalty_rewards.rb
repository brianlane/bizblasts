class CreateLoyaltyRewards < ActiveRecord::Migration[8.0]
  def change
    create_table :loyalty_rewards do |t|
      t.references :business, null: false, foreign_key: { on_delete: :cascade }
      t.references :loyalty_program, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.text :description, null: false
      t.integer :points_required, null: false
      t.boolean :active, default: true, null: false

      t.timestamps
    end
    
    add_index :loyalty_rewards, :active
    add_index :loyalty_rewards, :points_required
  end
end
