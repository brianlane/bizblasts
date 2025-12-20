# frozen_string_literal: true

class CreateJobFormSubmissions < ActiveRecord::Migration[8.1]
  def change
    create_table :job_form_submissions do |t|
      t.references :business, null: false, foreign_key: true
      t.references :booking, null: false, foreign_key: true
      t.references :job_form_template, null: false, foreign_key: true
      t.references :staff_member, foreign_key: true
      t.references :submitted_by_user, foreign_key: { to_table: :users }
      t.jsonb :responses, default: {}, null: false
      t.integer :status, default: 0, null: false
      t.datetime :submitted_at
      t.datetime :approved_at
      t.references :approved_by_user, foreign_key: { to_table: :users }
      t.text :notes

      t.timestamps
    end

    add_index :job_form_submissions, [:booking_id, :job_form_template_id], name: 'idx_job_form_submissions_booking_template'
    add_index :job_form_submissions, [:business_id, :status]
  end
end
