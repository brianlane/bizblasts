class CreateOauthFlashMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :oauth_flash_messages do |t|
      t.string :token, null: false
      t.string :notice
      t.string :alert
      t.datetime :expires_at, null: false
      t.boolean :used, null: false, default: false

      t.timestamps
    end
    add_index :oauth_flash_messages, :token, unique: true
    add_index :oauth_flash_messages, :expires_at
  end
end
