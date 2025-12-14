# frozen_string_literal: true

class AddAdpFieldsToStaffMembers < ActiveRecord::Migration[8.1]
  def change
    add_column :staff_members, :adp_employee_id, :string
    add_column :staff_members, :adp_pay_code, :string
    add_column :staff_members, :adp_department_code, :string
    add_column :staff_members, :adp_job_code, :string

    add_index :staff_members, :adp_employee_id
  end
end
