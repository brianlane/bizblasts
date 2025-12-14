# frozen_string_literal: true

class CreateAdpPayrollExportConfigs < ActiveRecord::Migration[8.1]
  def change
    create_table :adp_payroll_export_configs do |t|
      t.references :business, null: false, foreign_key: true, index: { unique: true }

      t.boolean :active, null: false, default: true

      # Common options; additional provider-specific keys live in config jsonb
      t.integer :rounding_minutes, null: false, default: 15
      t.boolean :round_total_hours, null: false, default: true

      # CSV format options / pay period defaults
      t.jsonb :config, null: false, default: {}

      t.timestamps
    end

    add_index :adp_payroll_export_configs, :active
  end
end
