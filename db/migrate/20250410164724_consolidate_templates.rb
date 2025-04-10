class ConsolidateTemplates < ActiveRecord::Migration[8.0]
  def change
    # Remove template_id foreign key from businesses table if it exists
    if foreign_key_exists?(:businesses, :templates)
      remove_foreign_key :businesses, :templates
    end
    if column_exists?(:businesses, :template_id)
      remove_reference :businesses, :template, index: { name: 'index_businesses_on_template_id' }, if_exists: true # Ensure index is removed too
    end

    # Drop the template_pages table and its foreign key if they exist
    if foreign_key_exists?(:template_pages, :templates)
      remove_foreign_key :template_pages, :templates
    end
    if table_exists?(:template_pages)
      drop_table :template_pages do |t|
        # Re-add columns based on the removed migration to ensure drop works
        t.bigint "template_id", null: false
        t.string "title"
        t.string "slug"
        t.integer "page_type"
        t.integer "position"
        t.jsonb "structure"
        t.datetime "created_at", null: false
        t.datetime "updated_at", null: false
        t.index ["template_id"], name: "index_template_pages_on_template_id"
      end
    end

    # Now drop the old templates table if it exists
    if table_exists?(:templates)
      drop_table :templates do |t|
        t.string "name"
        t.string "industry"
        t.integer "template_type"
        t.boolean "active"
        t.jsonb "structure"
        t.datetime "created_at", null: false
        t.datetime "updated_at", null: false
        # Indexes are dropped with the table
      end
    end

    # Remove unused columns from service_templates if they exist
    if column_exists?(:service_templates, :category)
      remove_column :service_templates, :category, :string
    end
    if column_exists?(:service_templates, :status)
      remove_column :service_templates, :status, :string # Assuming it was string based on admin usage
    end

    # Optional: Ensure required columns exist on service_templates if they were missing
    # add_column :service_templates, :industry, :string unless column_exists?(:service_templates, :industry)
    # add_column :service_templates, :template_type, :integer, default: 0, null: false unless column_exists?(:service_templates, :template_type)
    # add_column :service_templates, :structure, :jsonb unless column_exists?(:service_templates, :structure)

    # Add indexes if they don't exist
    # add_index :service_templates, :industry unless index_exists?(:service_templates, :industry)
    # add_index :service_templates, :template_type unless index_exists?(:service_templates, :template_type)

  end
end
