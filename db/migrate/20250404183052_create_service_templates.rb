class CreateServiceTemplates < ActiveRecord::Migration[8.0]
  def change
    create_table :service_templates do |t|
      t.string :name, null: false
      t.text :description
      t.string :category
      t.string :industry
      t.boolean :active, default: true
      t.string :status, default: 'draft'
      t.jsonb :features
      t.jsonb :pricing
      t.jsonb :content
      t.jsonb :settings
      t.datetime :published_at
      t.jsonb :metadata

      t.timestamps
    end

    add_index :service_templates, :name
    add_index :service_templates, :category
    add_index :service_templates, :industry
    add_index :service_templates, :status
    add_index :service_templates, :active
  end
end
