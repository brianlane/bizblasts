# frozen_string_literal: true

class CreateAdpPayrollExportRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :adp_payroll_export_runs do |t|
      t.references :business, null: false, foreign_key: true
      t.references :user, null: true, foreign_key: true

      t.integer :status, null: false, default: 0

      t.date :range_start, null: false
      t.date :range_end, null: false

      t.jsonb :options, null: false, default: {}
      t.jsonb :summary, null: false, default: {}
      t.jsonb :error_report, null: false, default: {}

      # Store generated CSV for audit / repeat downloads
      t.text :csv_data

      t.datetime :started_at
      t.datetime :finished_at

      t.timestamps
    end

    add_index :adp_payroll_export_runs, [:business_id, :created_at]
    add_index :adp_payroll_export_runs, :status
  end
end
