class AddCompoundIndexToInvalidatedSessions < ActiveRecord::Migration[8.0]
  def change
    # Add the suggested compound index for optimal blacklist lookup performance
    # This replaces the need for separate session_token and expires_at indexes
    add_index :invalidated_sessions, [:session_token, :expires_at],
              name: 'index_invalidated_sessions_on_token_and_expires_at'
  end
end
