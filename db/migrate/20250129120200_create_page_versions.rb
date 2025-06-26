class CreatePageVersions < ActiveRecord::Migration[8.0]
  def change
    create_table :page_versions do |t|
      t.references :page, null: false, foreign_key: true
      t.references :created_by, null: true, foreign_key: { to_table: :users }
      t.integer :version_number, null: false
      t.json :content_snapshot, null: false, default: {}
      t.integer :status, default: 0, null: false
      t.timestamp :published_at
      t.text :change_notes
      t.timestamps
    end

    add_index :page_versions, [:page_id, :version_number], unique: true
    add_index :page_versions, :status
    add_index :page_versions, :published_at
  end
end 