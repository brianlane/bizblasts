class ChangeIndustryToIntegerInServiceTemplates < ActiveRecord::Migration[8.0]
  def up
    # Add a temporary integer column
    add_column :service_templates, :industry_int, :integer

    # Map existing string values to integer values (optional, if data exists)
    # ServiceTemplate.reset_column_information
    # ServiceTemplate.find_each do |st|
    #   int_value = ServiceTemplate.industries[st.industry]
    #   st.update_column(:industry_int, int_value) if int_value
    # end

    # Remove the old string column
    remove_column :service_templates, :industry

    # Rename the new integer column to industry
    rename_column :service_templates, :industry_int, :industry

    # Add index back if it was removed (it should be dropped with remove_column)
    add_index :service_templates, :industry unless index_exists?(:service_templates, :industry)
  end

  def down
    # To make reversible, we'd need to store the string mapping
    # For simplicity, just recreate as string
    remove_index :service_templates, :industry, if_exists: true
    remove_column :service_templates, :industry
    add_column :service_templates, :industry, :string
    add_index :service_templates, :industry unless index_exists?(:service_templates, :industry)

    # Note: Data loss will occur on rollback without string mapping logic
    raise ActiveRecord::IrreversibleMigration, "Rollback would lose original string data if mapping wasn't performed."
  end
end
