class CreateServiceTemplates < ActiveRecord::Migration[8.0]
  def change
    create_table :service_templates do |t|
      t.string :name, null: false
      t.text :description
      t.string :category
      t.string :industry
      t.boolean :active, default: true
      t.jsonb :features, default: []
      t.jsonb :pricing, default: {}
      t.jsonb :content, default: {}
      t.jsonb :settings, default: {}
      t.string :status, default: 'draft'
      t.datetime :published_at
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :service_templates, :active
    add_index :service_templates, :category
    add_index :service_templates, :industry
    add_index :service_templates, :status
  end
end
