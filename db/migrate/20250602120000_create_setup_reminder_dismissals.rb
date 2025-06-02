class CreateSetupReminderDismissals < ActiveRecord::Migration[8.0]
  def change
    create_table :setup_reminder_dismissals do |t|
      t.references :user, null: false, foreign_key: true
      t.string :task_key, null: false
      t.datetime :dismissed_at, null: false
      t.timestamps
    end
    add_index :setup_reminder_dismissals, [:user_id, :task_key], unique: true
  end
end 