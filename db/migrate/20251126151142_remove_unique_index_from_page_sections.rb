# frozen_string_literal: true

class RemoveUniqueIndexFromPageSections < ActiveRecord::Migration[8.0]
  def up
    # Remove the overly restrictive unique index
    # The website builder legitimately allows multiple sections of the same type per page
    # (e.g., multiple text blocks, multiple images)
    remove_index :page_sections, name: 'index_page_sections_unique_per_page', if_exists: true
  end

  def down
    # Re-add the unique index (with cleanup first)
    execute <<-SQL
      DELETE FROM page_sections
      WHERE id NOT IN (
        SELECT MIN(id)
        FROM page_sections
        GROUP BY page_id, section_type
      )
    SQL

    add_index :page_sections, [:page_id, :section_type], unique: true, name: 'index_page_sections_unique_per_page'
  end
end
