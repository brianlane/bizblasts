class CreatePageSections < ActiveRecord::Migration[8.0]
  def change
    create_table :page_sections do |t|
      t.references :page, null: false, foreign_key: true
      t.integer :section_type
      t.text :content
      t.integer :position
      t.boolean :active

      t.timestamps
    end
  end
end
