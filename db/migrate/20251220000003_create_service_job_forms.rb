# frozen_string_literal: true

class CreateServiceJobForms < ActiveRecord::Migration[8.1]
  def change
    create_table :service_job_forms do |t|
      t.references :service, null: false, foreign_key: true
      t.references :job_form_template, null: false, foreign_key: true
      t.boolean :required, default: false, null: false
      t.integer :timing, default: 0, null: false

      t.timestamps
    end

    add_index :service_job_forms, [:service_id, :job_form_template_id], unique: true, name: 'idx_service_job_forms_unique'
  end
end
