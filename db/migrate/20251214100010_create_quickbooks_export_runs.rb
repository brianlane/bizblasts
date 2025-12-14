# frozen_string_literal: true

class CreateQuickbooksExportRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :quickbooks_export_runs do |t|
      t.references :business, null: false, foreign_key: true
      t.references :user, null: true, foreign_key: true

      t.integer :status, null: false, default: 0
      t.string :export_type, null: false, default: 'invoices'

      t.datetime :started_at
      t.datetime :finished_at

      # Inputs and outputs for audit/debug
      t.jsonb :filters, null: false, default: {}
      t.jsonb :summary, null: false, default: {}
      t.jsonb :error_report, null: false, default: {}

      t.timestamps
    end

    add_index :quickbooks_export_runs, [:business_id, :created_at]
    add_index :quickbooks_export_runs, :status
  end
end
