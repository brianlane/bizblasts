# frozen_string_literal: true

class CreatePolicyAcceptances < ActiveRecord::Migration[8.0]
  def change
    create_table :policy_acceptances do |t|
      t.references :user, null: false, foreign_key: true
      t.string :policy_type, null: false # 'terms_of_service', 'privacy_policy', 'acceptable_use_policy', 'return_policy'
      t.string :policy_version, null: false # e.g., 'v1.0', 'v1.1'
      t.datetime :accepted_at, null: false
      t.string :ip_address
      t.string :user_agent
      t.timestamps

      t.index [:user_id, :policy_type], name: 'index_policy_acceptances_on_user_and_type'
      t.index :policy_version
      t.index :accepted_at
    end
  end
end 