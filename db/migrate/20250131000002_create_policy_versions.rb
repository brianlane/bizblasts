# frozen_string_literal: true

class CreatePolicyVersions < ActiveRecord::Migration[8.0]
  def change
    create_table :policy_versions do |t|
      t.string :policy_type, null: false # 'terms_of_service', 'privacy_policy', 'acceptable_use_policy', 'return_policy'
      t.string :version, null: false # e.g., 'v1.0', 'v1.1'
      t.text :content # Optional: store policy content or reference
      t.string :termly_embed_id # Store Termly embed ID
      t.boolean :active, default: false
      t.boolean :requires_notification, default: false # For major changes requiring email notification
      t.datetime :effective_date
      t.text :change_summary # What changed in this version
      t.timestamps

      t.index [:policy_type, :version], unique: true
      t.index [:policy_type, :active]
      t.index :effective_date
    end
  end
end 