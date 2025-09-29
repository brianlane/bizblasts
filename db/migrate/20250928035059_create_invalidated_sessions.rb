class CreateInvalidatedSessions < ActiveRecord::Migration[8.0]
  def change
    create_table :invalidated_sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :session_token, null: false
      t.datetime :invalidated_at, null: false
      t.datetime :expires_at, null: false

      t.timestamps
    end

    # Add indexes for performance
    add_index :invalidated_sessions, :session_token, unique: true
    add_index :invalidated_sessions, :expires_at
    add_index :invalidated_sessions, [:user_id, :session_token]
  end
end
