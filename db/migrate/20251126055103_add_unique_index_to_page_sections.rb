# frozen_string_literal: true

class AddUniqueIndexToPageSections < ActiveRecord::Migration[8.0]
  def up
    # First, clean up any existing duplicates (keep the oldest one for each page/section_type combo)
    execute <<-SQL
      DELETE FROM page_sections
      WHERE id NOT IN (
        SELECT MIN(id)
        FROM page_sections
        GROUP BY page_id, section_type
      )
    SQL

    # Now add the unique index to prevent future duplicates
    add_index :page_sections, [:page_id, :section_type], unique: true, name: 'index_page_sections_unique_per_page'
  end

  def down
    remove_index :page_sections, name: 'index_page_sections_unique_per_page'
  end
end
