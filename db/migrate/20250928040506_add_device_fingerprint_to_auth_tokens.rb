class AddDeviceFingerprintToAuthTokens < ActiveRecord::Migration[8.0]
  def change
    add_column :auth_tokens, :device_fingerprint, :string

    # Add index for device fingerprint lookups (for potential future features)
    add_index :auth_tokens, :device_fingerprint
  end
end
