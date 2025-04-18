class CreateStaffAssignments < ActiveRecord::Migration[8.0]
  def change
    create_table :staff_assignments do |t|
      t.references :user, null: false, foreign_key: true
      t.references :service, null: false, foreign_key: true

      t.timestamps
    end
  end
end
