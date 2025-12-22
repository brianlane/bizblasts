# frozen_string_literal: true

class AddUniqueIndexToJobFormSubmissions < ActiveRecord::Migration[8.0]
  def change
    # Remove existing non-unique index
    remove_index :job_form_submissions, name: 'idx_job_form_submissions_booking_template',
                 if_exists: true

    # Add unique index to prevent duplicate submissions for the same booking and template
    add_index :job_form_submissions, [:booking_id, :job_form_template_id],
              unique: true,
              name: 'idx_job_form_submissions_booking_template_unique',
              if_not_exists: true
  end
end
