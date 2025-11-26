class SetDefaultActiveOnPageSections < ActiveRecord::Migration[7.1]
  def up
    # Update existing nil values to true
    execute <<-SQL
      UPDATE page_sections SET active = true WHERE active IS NULL
    SQL

    # Set default value for future records
    change_column_default :page_sections, :active, from: nil, to: true
    change_column_null :page_sections, :active, false
  end

  def down
    change_column_null :page_sections, :active, true
    change_column_default :page_sections, :active, from: true, to: nil
  end
end
