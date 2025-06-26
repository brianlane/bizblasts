class CreateWebsiteTemplates < ActiveRecord::Migration[8.0]
  def change
    create_table :website_templates do |t|
      t.string :name, null: false
      t.string :industry, null: false
      t.integer :template_type, default: 0, null: false
      t.json :structure, null: false, default: {}
      t.json :default_theme, null: false, default: {}
      t.text :preview_image_url
      t.text :description
      t.boolean :requires_premium, default: false, null: false
      t.boolean :active, default: true, null: false
      t.timestamps
    end

    add_index :website_templates, :industry
    add_index :website_templates, :template_type
    add_index :website_templates, [:active, :requires_premium]
  end
end 