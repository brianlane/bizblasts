class CreateAuthenticationBridges < ActiveRecord::Migration[8.0]
  def change
    create_table :authentication_bridges do |t|
      t.references :user, null: false, foreign_key: true
      t.string :token, null: false, limit: 64
      t.datetime :expires_at, null: false
      t.text :target_url, null: false
      t.datetime :used_at
      t.string :source_ip, limit: 45 # IPv6 support
      t.string :user_agent, limit: 500

      t.timestamps
    end
    
    # Add indexes for performance and security
    add_index :authentication_bridges, :token, unique: true
    add_index :authentication_bridges, :expires_at
    add_index :authentication_bridges, [:user_id, :created_at]
  end
end
