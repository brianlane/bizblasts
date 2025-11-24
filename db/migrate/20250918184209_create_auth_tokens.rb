class CreateAuthTokens < ActiveRecord::Migration[8.0]
  def change
    create_table :auth_tokens do |t|
      t.string :token, null: false
      t.integer :user_id, null: false
      t.text :target_url, null: false
      t.string :ip_address, null: false
      t.text :user_agent, null: false
      t.boolean :used, default: false, null: false
      t.datetime :expires_at, null: false

      t.timestamps
    end

    add_index :auth_tokens, :token, unique: true
    add_index :auth_tokens, :user_id
    add_index :auth_tokens, :expires_at
    add_index :auth_tokens, [:used, :expires_at]
    
    add_foreign_key :auth_tokens, :users
  end
end
