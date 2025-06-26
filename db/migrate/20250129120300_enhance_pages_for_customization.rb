class EnhancePagesForCustomization < ActiveRecord::Migration[8.0]
  def change
    add_column :pages, :status, :integer, default: 1, null: false
    add_column :pages, :template_applied, :string
    add_column :pages, :custom_theme_settings, :json, default: {}
    add_column :pages, :seo_title, :string
    add_column :pages, :seo_keywords, :text
    
    add_index :pages, :status
    add_index :pages, :template_applied
  end
end 