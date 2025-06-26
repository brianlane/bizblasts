class CreateWebsiteThemes < ActiveRecord::Migration[8.0]
  def change
    create_table :website_themes do |t|
      t.references :business, null: false, foreign_key: true
      t.string :name, null: false
      t.json :color_scheme, null: false, default: {}
      t.json :typography, null: false, default: {}
      t.json :layout_config, null: false, default: {}
      t.text :custom_css
      t.boolean :active, default: false, null: false
      t.timestamps
    end

    add_index :website_themes, [:business_id, :active]
    add_index :website_themes, :name
  end
end 