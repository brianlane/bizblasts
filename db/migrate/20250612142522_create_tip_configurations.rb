class CreateTipConfigurations < ActiveRecord::Migration[8.0]
  def change
    create_table :tip_configurations do |t|
      t.references :business, null: false, foreign_key: true
      t.json :default_tip_percentages, default: [15, 18, 20], null: false
      t.boolean :custom_tip_enabled, default: true, null: false
      t.text :tip_message
      t.timestamps
    end
    
    add_index :tip_configurations, :business_id, unique: true unless index_exists?(:tip_configurations, :business_id)
  end
end 