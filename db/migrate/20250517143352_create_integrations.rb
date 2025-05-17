class CreateIntegrations < ActiveRecord::Migration[7.1]
  def change
    create_table :integrations do |t|
      t.references :business, null: false, foreign_key: true
      t.integer :kind, null: false
      t.jsonb :config

      t.timestamps
    end
  end
end
