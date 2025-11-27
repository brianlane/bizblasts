class CreateEstimateVersions < ActiveRecord::Migration[8.0]
  def change
    create_table :estimate_versions do |t|
      t.references :estimate, null: false, foreign_key: true
      t.integer :version_number, null: false
      t.jsonb :snapshot, null: false # Full JSON snapshot of estimate + items
      t.text :change_notes
      t.datetime :created_at, null: false

      t.index [:estimate_id, :version_number], unique: true
    end

    # Add current version tracking to estimates
    add_column :estimates, :current_version, :integer, default: 1, null: false
    add_column :estimates, :total_versions, :integer, default: 1, null: false
  end
end
