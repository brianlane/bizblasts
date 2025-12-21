# frozen_string_literal: true

class AddIndexToJobFormSubmissionsStatus < ActiveRecord::Migration[8.0]
  def change
    add_index :job_form_submissions, [:business_id, :status],
              name: 'index_job_form_submissions_on_business_and_status',
              if_not_exists: true
  end
end
