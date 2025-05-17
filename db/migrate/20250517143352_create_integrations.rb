class CreateIntegrations < ActiveRecord::Migration[7.1]
  def change
    # Only create the table if it doesn't already exist
    unless table_exists?(:integrations)
      create_table :integrations do |t|
        t.references :business, null: false, foreign_key: true
        t.integer :kind, null: false
        t.jsonb :config

        t.timestamps
      end
    end
  end
end
