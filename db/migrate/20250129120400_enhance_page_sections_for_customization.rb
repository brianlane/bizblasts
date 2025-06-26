class EnhancePageSectionsForCustomization < ActiveRecord::Migration[8.0]
  def change
    add_column :page_sections, :section_config, :json, default: {}
    add_column :page_sections, :custom_css_classes, :string
    add_column :page_sections, :animation_type, :string
    add_column :page_sections, :background_settings, :json, default: {}
    
    # Add new section types
    change_column_default :page_sections, :section_type, from: 0, to: 0
    
    add_index :page_sections, :animation_type
  end
end 