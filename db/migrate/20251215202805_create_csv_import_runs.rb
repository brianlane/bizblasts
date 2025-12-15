class CreateCsvImportRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :csv_import_runs do |t|
      t.references :business, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.string :import_type, null: false
      t.integer :status, default: 0, null: false
      t.string :original_filename
      t.integer :total_rows, default: 0
      t.integer :processed_rows, default: 0
      t.integer :created_count, default: 0
      t.integer :updated_count, default: 0
      t.integer :skipped_count, default: 0
      t.integer :error_count, default: 0
      t.jsonb :summary, default: {}, null: false
      t.jsonb :error_report, default: {}, null: false
      t.datetime :started_at
      t.datetime :finished_at

      t.timestamps
    end

    add_index :csv_import_runs, [:business_id, :created_at]
    add_index :csv_import_runs, :status
    add_index :csv_import_runs, :import_type
  end
end
