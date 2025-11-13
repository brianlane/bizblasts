class AddOnDeleteCascadeToInvalidatedSessions < ActiveRecord::Migration[8.0]
  def change
    remove_foreign_key :invalidated_sessions, :users
    add_foreign_key :invalidated_sessions, :users, on_delete: :cascade
  end
end

